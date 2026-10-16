// CBT-01 fix loop 2 (re-audit of PR 165 at 2d9990e): the validators accept exactly the set
// design/19 allows, and every accepted collection of passives is representable in the snapshot.
//
// The flattening below is a test oracle, not the snapshot builder (that is ENG-06's, with
// design/15's formulas): it sums what §4 and §7.2 say to sum, saturates only where the documents
// say a sum saturates or is capped at use (`ARMOR_VS` at 63, FX-23; `KNOCKDOWN_FLAT` at 3 and the
// duration percents at 50, ENG-01 §3.1), and converts each result into its field, which panics if
// it does not fit. The loadouts are built from records the validators accept, placed as design/15
// places them: a prefix on the weapon, a suffix and an inscription on the weapon and the
// off-hand, an insignia and a rune on each of the 5 armor pieces, and one set's 2 bonuses. The
// sums the documents give no capacity rule for are escalated (REPORT.md, fix loop 2), not
// flattened here.
//
// What stays here are the oracle's flattenings, each across several modules (ENG-R1c, ruling 3);
// the validators' tests of one module are in `models::modifier`, `models::armor_set` and
// `types::passive`.
use grimworld_logic::models::armor_set::{ArmorSet, ArmorSetAssert, ArmorSetTrait};
use grimworld_logic::models::base::slot as base_slot;
use grimworld_logic::models::member_bar::{MemberBar, MemberBarTrait, QuickCast};
use grimworld_logic::models::member_kit::{MemberKit, MemberKitTrait};
use grimworld_logic::models::member_stats::{MemberStats, MemberStatsTrait};
use grimworld_logic::models::modifier::{Modifier, ModifierAssert, ModifierTrait, slot};
use grimworld_logic::types::combat::condition;
use grimworld_logic::types::effect::{guard, scope};
use grimworld_logic::types::passive::{
    HIT_ATTACK_SKILL, HIT_SPELL, HIT_WEAPON, Passive, PassiveAssert, PassiveTrait, id,
};

/// The weighted rating of the pieces and the shield, each personalised (F-21): 255 + 25 + 255 +
/// 25.
const RATINGS: i32 = 560;

#[generate_trait]
impl FixtureImpl of Fixture {
    fn passive(id: u8, param: u8, value: i16) -> Passive {
        PassiveTrait::new(id, param, 0, 0, value, value)
    }

    fn damage(guard: u8, scope: u8, value: i16) -> Passive {
        PassiveTrait::new(id::DAMAGE_PERCENT, 0, guard, scope, value, value)
    }

    fn penetration(scope: u8, value: i16) -> Passive {
        PassiveTrait::new(id::PENETRATION, 0, 0, scope, value, value)
    }

    fn armor(guard: u8, value: i16) -> Passive {
        PassiveTrait::new(id::ARMOR, 0, guard, 0, value, value)
    }

    /// A modifier of `slot`; an insignia is made for the chest (DS-23), the widest piece.
    fn modifier(slot: u8, benefit: Passive, cost: Passive) -> Modifier {
        if slot == slot::INSIGNIA {
            ModifierTrait::insignia(base_slot::CHEST, benefit, cost)
        } else {
            ModifierTrait::new(slot, benefit, cost)
        }
    }

    /// The passives an adventurer holds with these modifiers on every slot of their type and
    /// this set's two bonuses, after the content pipeline's checks: each modifier on its slot
    /// type, the modifiers together (`assert_catalogue`), the set.
    fn loadout(
        prefix: Modifier,
        suffix: Modifier,
        inscription: Modifier,
        insignia: Modifier,
        rune: Modifier,
        set: ArmorSet,
    ) -> Span<Passive> {
        assert(prefix.slot == slot::PREFIX && suffix.slot == slot::SUFFIX, 'slots');
        assert(inscription.slot == slot::INSCRIPTION && insignia.slot == slot::INSIGNIA, 'slots');
        assert(rune.slot == slot::RUNE, 'slots');
        ModifierAssert::assert_catalogue(
            array![prefix, suffix, inscription, insignia, rune].span(),
        );
        set.assert_legal();
        let mut held: Array<Passive> = array![];
        let placed = array![
            (prefix, 1_u8), (suffix, 2), (inscription, 2), (insignia, 5), (rune, 5),
        ];
        for (modifier, count) in placed {
            for _ in 0..count {
                held.append(modifier.benefit);
                held.append(modifier.cost);
            }
        }
        let [first, second] = set.bonuses;
        held.append(first);
        held.append(second);
        held.span()
    }

    /// The sum of the passives `id` of `guard` that apply to hits of `class` (design/19 §5.4: an
    /// attack skill's hit takes `WEAPON` and `ATTACK_SKILL`; `ALL` every class; a passive without
    /// a scope applies to every class), at their widest value.
    fn sum(held: Span<Passive>, id: u8, guard: u8, class: u8) -> i32 {
        let mut total: i32 = 0;
        for passive in held {
            if *passive.id == id && *passive.guard == guard && passive.applies_to(class) {
                total += (*passive.max).into();
            }
        }
        total
    }

    /// The sum of the passives `id` of `param`.
    fn sum_param(held: Span<Passive>, id: u8, param: u8) -> i32 {
        let mut total: i32 = 0;
        for passive in held {
            if *passive.id == id && *passive.param == param {
                total += (*passive.max).into();
            }
        }
        total
    }

    fn count(held: Span<Passive>, id: u8) -> u32 {
        let mut count = 0;
        for passive in held {
            if *passive.id == id {
                count += 1;
            }
        }
        count
    }

    fn at_most(value: i32, cap: i32) -> i32 {
        if value > cap {
            cap
        } else {
            value
        }
    }

    /// The oracle: `held` into the three snapshot words, each packed and unpacked. A sum that
    /// does not fit its field panics in its conversion.
    fn flatten(held: Span<Passive>, ratings: i32) -> (MemberStats, MemberBar, MemberKit) {
        let d = |g: u8, s: u8| -> i8 {
            Self::sum(held, id::DAMAGE_PERCENT, g, s).try_into().expect('damage sum overflows')
        };
        let p = |s: u8| -> u8 {
            Self::sum(held, id::PENETRATION, 0, s).try_into().expect('penetration overflows')
        };
        let unguarded = Self::sum(held, id::ARMOR, guard::ALWAYS, 0) + ratings;
        // Two quick-cast pairs at most.
        let mut pairs: Array<QuickCast> = array![];
        for passive in held {
            if *passive.id == id::QUICK_CAST_EVERY_N {
                pairs
                    .append(
                        QuickCast {
                            attribute: *passive.param, every: (*passive.max).try_into().unwrap(),
                        },
                    );
            }
        }
        assert(pairs.len() <= 2, 'more than 2 quick-cast pairs');
        while pairs.len() < 2 {
            pairs.append(Default::default());
        }
        let bar = MemberBar {
            skills: [0; 8],
            elite_slot: 255,
            damage: [
                d(guard::ALWAYS, HIT_WEAPON), d(guard::ALWAYS, HIT_ATTACK_SKILL),
                d(guard::ALWAYS, HIT_SPELL), d(guard::ABOVE_HALF, HIT_WEAPON),
                d(guard::ABOVE_HALF, HIT_ATTACK_SKILL), d(guard::ABOVE_HALF, HIT_SPELL),
            ],
            penetration: [p(HIT_WEAPON), p(HIT_ATTACK_SKILL), p(HIT_SPELL)],
            quick_cast: [*pairs[0], *pairs[1]],
            armor: unguarded.try_into().expect('armor overflows'),
        };
        // One condition's duration: one prefix, whose benefit and cost may name the same
        // condition, summed per condition then capped (CBT-9, design/19 §4). The builder agrees.
        let mut condition: u8 = 0;
        for passive in held {
            if *passive.id == id::CONDITION_DURATION {
                assert(condition == 0 || condition == *passive.param, 'more than one condition');
                condition = *passive.param;
            }
        }
        let percent: u8 = Self::at_most(
            Self::sum_param(held, id::CONDITION_DURATION, condition), 50,
        )
            .try_into()
            .unwrap();
        assert(MemberKitTrait::condition_duration(held) == (condition, percent), 'builder differs');
        let mut every: u8 = 0;
        for passive in held {
            if *passive.id == id::ADRENALINE_EVERY_N {
                let n: u8 = (*passive.max).try_into().unwrap();
                if every == 0 || n < every {
                    every = n;
                }
            }
        }
        let g = |guard: u8| -> i8 {
            Self::sum(held, id::ARMOR, guard, 0).try_into().expect('guarded armor overflows')
        };
        let kit = MemberKit {
            belt: [0; 4],
            life_steal: 0,
            energy_on_hit: 0,
            condition,
            condition_duration: percent,
            enchantment_duration: Self::at_most(Self::sum(held, id::ENCHANT_DURATION, 0, 0), 50)
                .try_into()
                .unwrap(),
            double_adrenaline_every: every,
            health_bonus: 0,
            armor_stance: g(guard::IN_STANCE),
            armor_enchanted: g(guard::ENCHANTED),
            knockdown: Self::at_most(Self::sum(held, id::KNOCKDOWN_FLAT, 0, 0), 3)
                .try_into()
                .unwrap(),
            halving: Self::count(held, id::HALVE_FIRST_HEAVY_HIT) > 0,
        };
        let vs = |t: u8| -> u8 {
            Self::at_most(Self::sum_param(held, id::ARMOR_VS, t), 63).try_into().unwrap()
        };
        let stats = MemberStats {
            armor_vs: [vs(1), vs(2), vs(3), vs(4), vs(5), vs(6), vs(7), vs(8), vs(9)],
            ..Default::default(),
        };
        assert(MemberBarTrait::unpack(MemberBarTrait::pack(bar)) == bar, 'bar round trip');
        assert(MemberKitTrait::unpack(MemberKitTrait::pack(kit)) == kit, 'kit round trip');
        assert(
            MemberStatsTrait::unpack(MemberStatsTrait::pack(stats)) == stats, 'stats round trip',
        );
        (stats, bar, kit)
    }

    /// A loadout whose prefix is `prefix` and whose other slots hold a knock-down tick, which any
    /// source may carry.
    fn with_prefix(prefix: Modifier) -> Span<Passive> {
        let knock = Self::passive(id::KNOCKDOWN_FLAT, 0, 1);
        let none: Passive = Default::default();
        Self::loadout(
            prefix,
            Self::modifier(slot::SUFFIX, knock, none),
            Self::modifier(slot::INSCRIPTION, knock, none),
            Self::modifier(slot::INSIGNIA, knock, none),
            Self::modifier(slot::RUNE, knock, none),
            ArmorSetTrait::new([1, 2, 3, 4, 5], [knock, knock]),
        )
    }
}

// Kept in `tests/`: it flattens across `models::modifier`, `models::armor_set` and the snapshot's
// three words (ruling 3).
// CBT-7 (flattening proof), damage: 7 sources of +18 above half on every scope reach 126; the
// held-item costs add −18 always to each scope, 5 of them; the insignias hold the audit's CBT-8
// pair, +18 in a stance and −18 enchanted.
#[test]
#[available_gas(l2_gas: 4122962)] // ceil(1.05 × 3926630 measured)
fn test_flatten_damage_extremes() {
    let up = Fixture::damage(guard::ABOVE_HALF, scope::ALL, 18);
    let down = Fixture::damage(guard::ALWAYS, scope::ALL, -18);
    let held = Fixture::loadout(
        Fixture::modifier(slot::PREFIX, up, down),
        Fixture::modifier(slot::SUFFIX, up, down),
        Fixture::modifier(slot::INSCRIPTION, up, down),
        Fixture::modifier(
            slot::INSIGNIA,
            Fixture::armor(guard::IN_STANCE, 18),
            Fixture::armor(guard::ENCHANTED, -18),
        ),
        Fixture::modifier(slot::RUNE, Fixture::armor(guard::ALWAYS, 255), Default::default()),
        ArmorSetTrait::new([1, 2, 3, 4, 5], [up, up]),
    );
    let (_, bar, kit) = Fixture::flatten(held, RATINGS);
    assert(bar.damage == [-90, -90, -90, 126, 126, 126], 'damage sums');
    assert(kit.armor_stance == 90 && kit.armor_enchanted == -90, 'guarded sums');
    assert(bar.armor == 5 * 255 + 560, 'unguarded');
}

// Kept in `tests/`: it flattens across `models::modifier`, `models::armor_set` and the snapshot's
// three words (ruling 3).
// CBT-7, penetration and guarded armor at their counts: 7 × 36 = 252; 7 × −18 = −126; the
// unguarded armor at every held-item and armor slot, −255, without ratings.
#[test]
#[available_gas(l2_gas: 8095878)] // ceil(1.05 × 7710360 measured)
fn test_flatten_penetration_and_armor_extremes() {
    let pierce = Fixture::penetration(scope::ALL, 36);
    let low = Fixture::armor(guard::ALWAYS, -255);
    let held = Fixture::loadout(
        Fixture::modifier(slot::PREFIX, pierce, low),
        Fixture::modifier(slot::SUFFIX, pierce, low),
        Fixture::modifier(slot::INSCRIPTION, pierce, low),
        Fixture::modifier(slot::INSIGNIA, Fixture::armor(guard::IN_STANCE, -18), low),
        Fixture::modifier(slot::RUNE, low, Default::default()),
        ArmorSetTrait::new(
            [1, 2, 3, 4, 5],
            [Fixture::armor(guard::IN_STANCE, -18), Fixture::armor(guard::IN_STANCE, -18)],
        ),
    );
    let (_, bar, kit) = Fixture::flatten(held, 0);
    assert(bar.penetration == [180, 180, 180], 'penetration: 5 held slots');
    assert(kit.armor_stance == -126, 'guarded: 7 sources');
    assert(bar.armor == -15 * 255, 'unguarded: 15 slots');
    // Penetration's 7th source: the set's two bonuses.
    let held = Fixture::loadout(
        Fixture::modifier(slot::PREFIX, pierce, Default::default()),
        Fixture::modifier(slot::SUFFIX, pierce, Default::default()),
        Fixture::modifier(slot::INSCRIPTION, pierce, Default::default()),
        Fixture::modifier(slot::INSIGNIA, low, Default::default()),
        Fixture::modifier(slot::RUNE, low, Default::default()),
        ArmorSetTrait::new([1, 2, 3, 4, 5], [pierce, pierce]),
    );
    let (_, bar, _) = Fixture::flatten(held, 0);
    assert(bar.penetration == [252, 252, 252], 'penetration: 7 sources');
}

// Kept in `tests/`: it flattens across `models::modifier`, `models::armor_set` and the snapshot's
// three words (ruling 3).
// CBT-7, the saturated and capped sums, each at the widest value a passive may carry: `ARMOR_VS`
// at 63 (FX-23), knock-down at 3 and the duration percents at 50 (ENG-01 §3.1); one condition
// (one prefix); two quick-cast pairs (one slot type, on the weapon and the off-hand).
#[test]
// Under design/20's per-source bounds (D-160): armor against a type 7 a source on 9 sources is
// 63; knock-down 1 a source on 13 is 13, saturated at 3; enchantment 20 a source on 7 is 140,
// saturated at 50; the condition 33.
#[available_gas(l2_gas: 4192209)] // ceil(1.05 × 3992580 measured)
fn test_flatten_saturated_extremes() {
    let vs = Fixture::passive(id::ARMOR_VS, 1, 7);
    let knock = Fixture::passive(id::KNOCKDOWN_FLAT, 0, 1);
    let enchant = Fixture::passive(id::ENCHANT_DURATION, 0, 20);
    let held = Fixture::loadout(
        Fixture::modifier(
            slot::PREFIX, Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 33), vs,
        ),
        Fixture::modifier(slot::SUFFIX, enchant, knock),
        Fixture::modifier(slot::INSCRIPTION, Fixture::passive(id::QUICK_CAST_EVERY_N, 3, 255), vs),
        Fixture::modifier(slot::INSIGNIA, knock, enchant),
        Fixture::modifier(slot::RUNE, vs, knock),
        ArmorSetTrait::new([1, 2, 3, 4, 5], [knock, vs]),
    );
    let (stats, bar, kit) = Fixture::flatten(held, RATINGS);
    assert(stats.armor_vs == [63, 0, 0, 0, 0, 0, 0, 0, 0], 'armor vs saturated');
    assert(kit.knockdown == 3 && kit.enchantment_duration == 50, 'capped');
    assert(kit.condition == condition::BLEEDING && kit.condition_duration == 33, 'one condition');
    let pair = QuickCast { attribute: 3, every: 255 };
    assert(bar.quick_cast == [pair, pair], 'two pairs');
}

// Kept in `tests/`: it flattens across `models::modifier`, `models::armor_set` and the snapshot's
// three words (ruling 3).
// CBT-9 (CBT-01's audit): a prefix whose benefit and cost name the same condition is legal, and
// the snapshot sums them per condition. The audit's 33 + 10 is above DS-5's ≤ 33 on a prefix
// (D-160; refused below): Bleeding 20 + 13 = 33. The oracle and the builder agree.
#[test]
#[available_gas(l2_gas: 4249319)] // ceil(1.05 × 4046970 measured)
fn test_same_condition_summed() {
    let prefix = Fixture::modifier(
        slot::PREFIX,
        Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 20),
        Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 13),
    );
    prefix.assert_legal();
    let (_, _, kit) = Fixture::flatten(Fixture::with_prefix(prefix), 0);
    assert(kit.condition == condition::BLEEDING && kit.condition_duration == 33, '20 + 13');
}

// Kept in `tests/`: it flattens across `models::modifier`, `models::armor_set` and the snapshot's
// three words (ruling 3).
// CBT-8 (fix loop 3), flattened: every held-item and armor slot holds two unguarded `ARMOR`
// passives, +255 (the benefit, the cost) and the set's two bonuses: 32 contributions, 32 × 255 +
// the personalised ratings = 8,720 ≤ 9,995; at −255 without ratings, −8,160.
#[test]
#[available_gas(l2_gas: 8145554)] // ceil(1.05 × 7757670 measured)
fn test_flatten_unguarded_armor_extremes() {
    let high = Fixture::armor(0, 255);
    let low = Fixture::armor(0, -255);
    let held = Fixture::loadout(
        Fixture::modifier(slot::PREFIX, high, high),
        Fixture::modifier(slot::SUFFIX, high, high),
        Fixture::modifier(slot::INSCRIPTION, high, high),
        Fixture::modifier(slot::INSIGNIA, high, high),
        Fixture::modifier(slot::RUNE, high, high),
        ArmorSetTrait::new([1, 2, 3, 4, 5], [high, high]),
    );
    let (_, bar, _) = Fixture::flatten(held, RATINGS);
    assert(bar.armor == 32 * 255 + 560, 'unguarded +8,720');
    let held = Fixture::loadout(
        Fixture::modifier(slot::PREFIX, low, low),
        Fixture::modifier(slot::SUFFIX, low, low),
        Fixture::modifier(slot::INSCRIPTION, low, low),
        Fixture::modifier(slot::INSIGNIA, low, low),
        Fixture::modifier(slot::RUNE, low, low),
        ArmorSetTrait::new([1, 2, 3, 4, 5], [low, low]),
    );
    let (_, bar, _) = Fixture::flatten(held, 0);
    assert(bar.armor == -32 * 255, 'unguarded -8,160');
}

// Kept in `tests/`: it flattens across `models::modifier`, `models::armor_set` and the snapshot's
// three words (ruling 3).
// CBT-2 (fix loop 3): an attack skill's hit takes `WEAPON` and `ATTACK_SKILL` (design/19 §5.4).
// One `WEAPON +18` flattens to 18 on plain weapon hits and on attack skills, 0 on spells.
#[test]
#[available_gas(l2_gas: 4003146)] // ceil(1.05 × 3812520 measured)
fn test_flatten_weapon_scope_on_attack_skills() {
    let none: Passive = Default::default();
    let weapon = Fixture::damage(guard::ALWAYS, scope::WEAPON, 18);
    let held = Fixture::loadout(
        Fixture::modifier(slot::PREFIX, weapon, none),
        Fixture::modifier(slot::SUFFIX, Fixture::armor(0, 1), none),
        Fixture::modifier(slot::INSCRIPTION, Fixture::armor(0, 1), none),
        Fixture::modifier(slot::INSIGNIA, Fixture::armor(0, 1), none),
        Fixture::modifier(slot::RUNE, Fixture::armor(0, 1), none),
        ArmorSetTrait::new([1, 2, 3, 4, 5], [none, none]),
    );
    let (_, bar, _) = Fixture::flatten(held, 0);
    assert(bar.damage == [18, 18, 0, 0, 0, 0], 'weapon applies to attack skills');
}

// Kept in `tests/`: it flattens across `models::modifier`, `models::armor_set` and the snapshot's
// three words (ruling 3).
// CBT-2, the worst overlap: each held-item slot holds `WEAPON` and `ATTACK_SKILL` in both
// orderings (benefit then cost, cost then benefit) at the most a source may add, 9 + 9 and 18 +
// 18 of penetration; the set's two bonuses are `ALL`. The attack-skill sums reach the counted
// bound exactly: damage 5 × 18 + 2 × 18 = 126, penetration 5 × 36 + 2 × 36 = 252.
#[test]
#[available_gas(l2_gas: 8193234)] // ceil(1.05 × 7803080 measured)
fn test_flatten_worst_scope_overlap() {
    let weapon = Fixture::damage(guard::ABOVE_HALF, scope::WEAPON, 9);
    let attack = Fixture::damage(guard::ABOVE_HALF, scope::ATTACK_SKILL, 9);
    let all = Fixture::damage(guard::ABOVE_HALF, scope::ALL, 18);
    let held = Fixture::loadout(
        Fixture::modifier(slot::PREFIX, weapon, attack),
        Fixture::modifier(slot::SUFFIX, attack, weapon),
        Fixture::modifier(slot::INSCRIPTION, weapon, attack),
        Fixture::modifier(slot::INSIGNIA, Fixture::armor(0, 1), Default::default()),
        Fixture::modifier(slot::RUNE, Fixture::armor(0, 1), Default::default()),
        ArmorSetTrait::new([1, 2, 3, 4, 5], [all, all]),
    );
    let (_, bar, _) = Fixture::flatten(held, 0);
    assert(bar.damage == [0, 0, 0, 81, 126, 36], 'damage per hit class');
    let weapon = Fixture::penetration(scope::WEAPON, 18);
    let attack = Fixture::penetration(scope::ATTACK_SKILL, 18);
    let all = Fixture::penetration(scope::ALL, 36);
    let held = Fixture::loadout(
        Fixture::modifier(slot::PREFIX, attack, weapon),
        Fixture::modifier(slot::SUFFIX, weapon, attack),
        Fixture::modifier(slot::INSCRIPTION, attack, weapon),
        Fixture::modifier(slot::INSIGNIA, Fixture::armor(0, 1), Default::default()),
        Fixture::modifier(slot::RUNE, Fixture::armor(0, 1), Default::default()),
        ArmorSetTrait::new([1, 2, 3, 4, 5], [all, all]),
    );
    let (_, bar, _) = Fixture::flatten(held, 0);
    assert(bar.penetration == [162, 252, 72], 'penetration per hit class');
}
