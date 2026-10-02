// CBT-01 fix loop 1 (audit of PR 165 at b5bce2d, CBT-1 to CBT-6): the content validators refuse
// exactly what design/19 excludes and accept exactly what it allows. Each `*_refused` test below
// is a record the code at b5bce2d accepted; the other tests are the boundaries still accepted, and
// the snapshot's capacity derived from the sources the validators allow.
use grimworld_logic::models::armor_set::{ArmorSetAssert, ArmorSetTrait};
use grimworld_logic::models::base::slot as base_slot;
use grimworld_logic::models::item::{ItemAssert, ItemTrait, class};
use grimworld_logic::models::modifier::{ModifierAssert, ModifierTrait, slot};
use grimworld_logic::models::skill::{SkillAssert, SkillTrait};
use grimworld_logic::snapshot::{QuickCast, QuickCastTrait};
use grimworld_logic::types::combat::{condition, skill_kind};
use grimworld_logic::types::effect::{Entry, EntryAssert, filter, guard, kind, scope, shape, target};
use grimworld_logic::types::passive::{MAX_DAMAGE_PERCENT, Passive, PassiveAssert, PassiveTrait, id};

#[generate_trait]
impl FixtureImpl of Fixture {
    fn passive(id: u8, param: u8, value: i16) -> Passive {
        PassiveTrait::new(id, param, 0, 0, value, value)
    }

    /// `DAMAGE_PERCENT +18`, the widest.
    fn damage() -> Passive {
        Self::passive(id::DAMAGE_PERCENT, 0, MAX_DAMAGE_PERCENT)
    }

    /// `ARMOR +10 while in a stance` (design/15's insignia).
    fn stance_armor() -> Passive {
        PassiveTrait::new(id::ARMOR, 0, guard::IN_STANCE, 0, 10, 10)
    }

    fn quick_cast() -> Passive {
        PassiveTrait::new(id::QUICK_CAST_EVERY_N, 4, 0, 0, 5, 5)
    }

    /// A modifier of `benefit` on `slot`, without a cost.
    /// `benefit` on a modifier of `slot`; an insignia is made for the chest (DS-23).
    fn on(slot: u8, benefit: Passive) {
        if slot == slot::INSIGNIA {
            ModifierTrait::insignia(base_slot::CHEST, benefit, Default::default()).assert_legal();
        } else {
            ModifierTrait::new(slot, benefit, Default::default()).assert_legal();
        }
    }

    fn preparation(d0: u16, d12: u16, charges: u8) -> Entry {
        Entry {
            kind: kind::ON_ATTACK_CONDITION,
            param: condition::POISON,
            v0: 1,
            v12: 1,
            d0,
            d12,
            charges,
            target: target::SELF,
            shape: shape::SINGLE,
            ..Default::default(),
        }
    }

    fn attack_with(entry: Entry) {
        SkillTrait::new(
            1,
            2,
            skill_kind::ATTACK,
            0,
            4,
            0,
            5,
            1,
            target::FOE,
            false,
            [entry, Default::default(), Default::default()],
        )
            .assert_legal();
    }

    /// An attack skill's hit modifier on the attacked foe.
    fn modifier_on_foe(kind: u8) -> Entry {
        Entry {
            kind, v0: 1, v12: 1, target: target::FOE, shape: shape::SINGLE, ..Default::default(),
        }
    }
}

// CBT-1: each passive's `param` lies in the enumeration its id names (fix loop 2: an attribute
// is any `u8`, its id space not being settled; see `test_capacity`).
#[test]
#[should_panic(expected: 'passive: param')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_armor_vs_type_255_refused() {
    Fixture::passive(id::ARMOR_VS, 255, 1).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: param')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_armor_vs_type_0_refused() {
    Fixture::passive(id::ARMOR_VS, 0, 1).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: param')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_damage_type_10_refused() {
    Fixture::passive(id::DAMAGE_TYPE, 10, 0).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: param')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_condition_duration_condition_10_refused() {
    Fixture::passive(id::CONDITION_DURATION, 10, 33).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: param')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_energy_cost_profession_7_refused() {
    Fixture::passive(id::ENERGY_COST, 7, -2).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: param')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_param_on_max_health_refused() {
    Fixture::passive(id::MAX_HEALTH, 1, 30).assert_legal();
}

// CBT-1: a scope above 3 is refused by the pipeline's check, not only by the packer.
#[test]
#[should_panic(expected: 'passive: scope')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_damage_percent_scope_4_refused() {
    PassiveTrait::new(id::DAMAGE_PERCENT, 0, 0, 4, 1, 1).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: scope')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_penetration_scope_4_refused() {
    PassiveTrait::new(id::PENETRATION, 0, 0, 4, 1, 1).assert_legal();
}

// CBT-1: values within what §4 and §7.2 state (fix loop 2: a saturated aggregate bounds no
// single passive; see `test_capacity`).
#[test]
#[should_panic(expected: 'passive: value out of bounds')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_armor_vs_negative_refused() {
    Fixture::passive(id::ARMOR_VS, 1, -1).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: value out of bounds')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_damage_type_with_a_value_refused() {
    Fixture::passive(id::DAMAGE_TYPE, 4, 1).assert_legal();
}

// CBT-1: through the containing record.
#[test]
#[should_panic(expected: 'passive: param')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_modifier_armor_vs_type_255_refused() {
    Fixture::on(slot::SUFFIX, Fixture::passive(id::ARMOR_VS, 255, 5));
}

// CBT-1: the ends of every domain are accepted.
#[test]
#[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
fn test_passive_domains_accepted() {
    Fixture::passive(id::ARMOR_VS, 1, 0).assert_legal();
    Fixture::passive(id::ARMOR_VS, 9, 63).assert_legal();
    Fixture::passive(id::DAMAGE_TYPE, 1, 0).assert_legal();
    Fixture::passive(id::DAMAGE_TYPE, 9, 0).assert_legal();
    Fixture::passive(id::CONDITION_DURATION, 1, 0).assert_legal();
    Fixture::passive(id::CONDITION_DURATION, 9, 63).assert_legal();
    PassiveTrait::new(id::QUICK_CAST_EVERY_N, 0, 0, 0, 1, 1).assert_legal();
    PassiveTrait::new(id::QUICK_CAST_EVERY_N, 15, 0, 0, 255, 255).assert_legal();
    Fixture::passive(id::ATTRIBUTE, 15, -3).assert_legal();
    Fixture::passive(id::ENERGY_COST, 1, -2).assert_legal();
    Fixture::passive(id::ENERGY_COST, 6, -2).assert_legal();
    Fixture::passive(id::LIFE_STEAL_ON_HIT, 0, 255).assert_legal();
    Fixture::passive(id::RATING_PERCENT, 0, 10).assert_legal();
    Fixture::passive(id::HALVE_FIRST_HEAVY_HIT, 0, 0).assert_legal();
    PassiveTrait::new(id::DAMAGE_PERCENT, 0, 0, scope::ALL, -18, 18).assert_legal();
    PassiveTrait::new(id::PENETRATION, 0, 0, scope::ALL, 0, 36).assert_legal();
}

// CBT-2: design/19 §7.2's sources. The audit's case: an insignia giving `DAMAGE_PERCENT +18`.
#[test]
#[should_panic(expected: 'passive: not on this source')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_damage_percent_on_insignia_refused() {
    Fixture::on(slot::INSIGNIA, Fixture::damage());
}

#[test]
#[should_panic(expected: 'passive: not on this source')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_damage_percent_on_rune_refused() {
    Fixture::on(slot::RUNE, Fixture::damage());
}

#[test]
#[should_panic(expected: 'passive: not on this source')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_penetration_on_insignia_refused() {
    Fixture::on(slot::INSIGNIA, Fixture::passive(id::PENETRATION, 0, 4));
}

#[test]
#[should_panic(expected: 'passive: not on this source')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_guarded_armor_on_prefix_refused() {
    Fixture::on(slot::PREFIX, Fixture::stance_armor());
}

#[test]
#[should_panic(expected: 'passive: not on this source')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_quick_cast_on_rune_refused() {
    Fixture::on(slot::RUNE, Fixture::quick_cast());
}

#[test]
#[should_panic(expected: 'passive: not on this source')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_quick_cast_set_bonus_refused() {
    ArmorSetTrait::new([1, 2, 3, 4, 5], [Fixture::quick_cast(), Default::default()]).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: not on this source')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_condition_duration_on_suffix_refused() {
    Fixture::on(slot::SUFFIX, Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 33));
}

#[test]
#[should_panic(expected: 'passive: not on this source')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_condition_duration_set_bonus_refused() {
    let rending = Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 33);
    ArmorSetTrait::new([1, 2, 3, 4, 5], [rending, Default::default()]).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: not on this source')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_damage_type_set_bonus_refused() {
    let fire = Fixture::passive(id::DAMAGE_TYPE, 4, 0);
    ArmorSetTrait::new([1, 2, 3, 4, 5], [fire, Default::default()]).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: not on this source')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_damage_type_on_insignia_refused() {
    Fixture::on(slot::INSIGNIA, Fixture::passive(id::DAMAGE_TYPE, 4, 0));
}

#[test]
#[should_panic(expected: 'passive: not on this source')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_rating_percent_on_a_modifier_refused() {
    Fixture::on(slot::INSIGNIA, Fixture::passive(id::RATING_PERCENT, 0, 10));
}

// A cost is a passive of its slot too: a `DAMAGE_PERCENT` drawback on an insignia.
#[test]
#[should_panic(expected: 'passive: not on this source')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_cost_on_a_forbidden_source_refused() {
    let health = Fixture::passive(id::MAX_HEALTH, 0, 15);
    let drawback = Fixture::passive(id::DAMAGE_PERCENT, 0, -5);
    ModifierTrait::new(slot::INSIGNIA, health, drawback).assert_legal();
}

// A counted statistic held twice by one modifier would count one source twice.
#[test]
#[should_panic(expected: 'passive: source adds too much')]
#[available_gas(l2_gas: 42809)] // ceil(1.05 × 40770 measured)
fn test_damage_percent_as_benefit_and_cost_refused() {
    let drawback = Fixture::passive(id::DAMAGE_PERCENT, 0, 18);
    ModifierTrait::new(slot::INSCRIPTION, Fixture::damage(), drawback).assert_legal();
}

// CBT-2: the sources design/19 allows are accepted.
#[test]
#[available_gas(l2_gas: 1529357)] // ceil(1.05 × 1456530 measured)
fn test_sources_accepted() {
    Fixture::on(slot::PREFIX, Fixture::damage());
    Fixture::on(slot::SUFFIX, Fixture::damage());
    Fixture::on(slot::INSCRIPTION, Fixture::damage());
    Fixture::on(slot::PREFIX, Fixture::passive(id::PENETRATION, 0, 4));
    Fixture::on(slot::INSIGNIA, Fixture::stance_armor());
    Fixture::on(slot::INSCRIPTION, Fixture::quick_cast());
    Fixture::on(slot::PREFIX, Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 33));
    Fixture::on(slot::PREFIX, Fixture::passive(id::DAMAGE_TYPE, 4, 0));
    Fixture::on(slot::RUNE, Fixture::passive(id::ARMOR, 0, 5));
    Fixture::on(slot::RUNE, Fixture::passive(id::ATTRIBUTE, 3, 2));
    // "+15 % damage, −5 energy" (design/15): a counted benefit with an uncounted cost.
    let energy = Fixture::passive(id::MAX_ENERGY, 0, -5);
    ModifierTrait::new(slot::INSCRIPTION, Fixture::damage(), energy).assert_legal();
    // Hob-breaker: the stance insignia's armor as a bonus, knock-down +1 a bonus (DS-5: ≤ 1).
    let one = Fixture::passive(id::KNOCKDOWN_FLAT, 0, 1);
    ArmorSetTrait::new([1, 2, 3, 4, 5], [one, one]).assert_legal();
    ArmorSetTrait::new([1, 2, 3, 4, 5], [Fixture::damage(), Fixture::stance_armor()])
        .assert_legal();
}

// CBT-3: an attack's hit modifier takes the attacked foe: `FOES`.
#[test]
#[should_panic(expected: 'carrier: modifier set')]
// gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once a
// call) and the actors their positions
#[available_gas(l2_gas: 88169)] // ceil(1.05 × 83970 measured)
fn test_attack_bonus_on_allies_refused() {
    let bonus = Fixture::modifier_on_foe(kind::ATTACK_BONUS);
    Fixture::attack_with(Entry { filter: filter::ALLIES, ..bonus });
}

#[test]
#[should_panic(expected: 'carrier: modifier set')]
// gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once a
// call) and the actors their positions
#[available_gas(l2_gas: 88368)] // ceil(1.05 × 84160 measured)
fn test_attack_hit_penetration_on_allies_refused() {
    let pierce = Fixture::modifier_on_foe(kind::HIT_PENETRATION);
    Fixture::attack_with(Entry { filter: filter::ALLIES, ..pierce });
}

#[test]
// gas: raised, CBT-05a: the content's sheets carry the executor's fields (entries decoded once a
// call) and the actors their positions
#[available_gas(l2_gas: 413196)] // ceil(1.05 × 393520 measured)
fn test_attack_modifiers_on_foes_accepted() {
    Fixture::attack_with(Fixture::modifier_on_foe(kind::ATTACK_BONUS));
    Fixture::attack_with(Fixture::modifier_on_foe(kind::HIT_PENETRATION));
}

// CBT-4: without charges, a preparation's duration is positive at every rank (ranks 0 and 15).
#[test]
#[should_panic(expected: 'entry: neither d nor charges')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_preparation_falling_to_0_at_15_refused() {
    // The audit's case: 5 + trunc(−4 × 15 / 12) = 0.
    Fixture::preparation(5, 1, 0).assert_legal();
}

#[test]
#[should_panic(expected: 'entry: neither d nor charges')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_preparation_falling_by_one_refused() {
    // 1 + trunc(−15 / 12) = 0.
    Fixture::preparation(1, 0, 0).assert_legal();
}

#[test]
#[should_panic(expected: 'entry: neither d nor charges')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_preparation_rising_from_0_refused() {
    Fixture::preparation(0, 5, 0).assert_legal();
}

#[test]
#[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
fn test_preparation_boundaries_accepted() {
    // 4 + trunc(−3 × 15 / 12) = 1; 1 at both ends; rising from 1 to exactly 43,688 at rank 15
    // (1 + trunc(34,950 × 15 / 12)); charges without a duration.
    Fixture::preparation(4, 1, 0).assert_legal();
    Fixture::preparation(1, 1, 0).assert_legal();
    Fixture::preparation(1, 34951, 0).assert_legal();
    Fixture::preparation(0, 0, 1).assert_legal();
    Fixture::preparation(5, 1, 1).assert_legal();
}

// CBT-5: a non-potion's entry is the empty entry, every field 0.
#[test]
#[should_panic(expected: 'entry: empty with a field')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_ingredient_with_a_stray_field_refused() {
    let stray = Entry { v0: 1, ..Default::default() };
    ItemTrait::new(class::INGREDIENT, 1, 1, 1, 3, stray, 0, 0).assert_legal();
}

#[test]
#[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
fn test_ingredient_empty_entry_accepted() {
    ItemTrait::new(class::INGREDIENT, 1, 1, 1, 3, Default::default(), 0, 0).assert_legal();
}

// CBT-6: the quick-cast pair's packing, scoped in its trait.
#[test]
#[available_gas(l2_gas: 11456)] // ceil(1.05 × 10910 measured)
fn test_quick_cast_trait() {
    let top = QuickCast { attribute: 15, every: 255 };
    assert(top.pack() == 0xFFF, '12 bits');
    assert(QuickCastTrait::unpack(0xFFF) == top, 'round trip');
}

#[test]
#[should_panic(expected: 'snapshot: quick-cast attribute')]
#[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
fn test_quick_cast_trait_refused() {
    QuickCast { attribute: 16, every: 1 }.pack();
}
