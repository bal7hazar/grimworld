// The combat's interfaces (CBT-01, docs/design/19-effects.md): the effect entry (§2), passives
// (§4), the records that carry them (§7.2, §7.3) and the enumerations (§7.1). Every record and
// word packs and unpacks losslessly at its bounds, sits at its documented bits, fits its part
// count and refuses a value too wide; the content pipeline's checks (reads, bounds, the legal
// carriers of §5.14) accept the design's own skills and refuse each illegal combination.
use grimworld_logic::content::{ARMOR_SET, CASTE, ITEM, MODIFIER, Record, SKILL, parts};
use grimworld_logic::helpers::signed::SignedTrait;
use grimworld_logic::models::armor_set::{ArmorSet, ArmorSetAssert, ArmorSetRecord, ArmorSetTrait};
use grimworld_logic::models::caste::{Caste, CasteAssert, CasteRecord, CasteTrait, WeaponTrait};
use grimworld_logic::models::item::{Item, ItemAssert, ItemRecord, ItemTrait, class};
use grimworld_logic::models::modifier::{
    Modifier, ModifierAssert, ModifierRecord, ModifierTrait, slot,
};
use grimworld_logic::models::skill::{Skill, SkillAssert, SkillRecord, SkillTrait};
use grimworld_logic::packing::LIVE;
use grimworld_logic::types::combat::{
    HitClass, Placer, PlacerTrait, condition, damage, skill_kind, weapon,
};
use grimworld_logic::types::effect::{
    ENTRY_BOUND, Entry, EntryAssert, EntryTrait, KindClass, filter, guard, kind, scope, shape,
    target,
};
use grimworld_logic::types::passive::{Passive, PassiveAssert, PassiveTrait, id};

const TWO_128: felt252 = 0x100000000000000000000000000000000;

/// The entries and records these tests start from: design/03's starter skills as design/19 §8
/// writes them (values illustrative).
#[generate_trait]
impl FixtureImpl of Fixture {
    /// An entry of `kind` on the attacked foe, every other field 0.
    fn on_foe(kind: u8) -> Entry {
        Entry { kind, target: target::FOE, shape: shape::SINGLE, ..Default::default() }
    }

    fn damage(kind: u8, v0: i16, v12: i16) -> Entry {
        Entry { param: kind, v0, v12, ..Self::on_foe(kind::DAMAGE) }
    }

    fn inflict(condition: u8, v0: i16, v12: i16) -> Entry {
        Entry { param: condition, v0, v12, ..Self::on_foe(kind::CONDITION) }
    }

    fn on_self(kind: u8) -> Entry {
        Entry { kind, target: target::SELF, shape: shape::SINGLE, ..Default::default() }
    }

    fn skill(kind: u8, entries: [Entry; 3]) -> Skill {
        SkillTrait::new(1, 2, kind, 5, 0, 1, 10, 6, target::FOE, false, entries)
    }

    /// Cinder Ring: fire damage 20…80 and Burning 1…3 on adjacent foes (`SELF`, `RING_1`).
    fn cinder_ring() -> Skill {
        let ring = |entry: Entry| -> Entry {
            Entry { target: target::SELF, shape: shape::RING_1, filter: filter::FOES, ..entry }
        };
        Self::skill(
            skill_kind::SPELL,
            [
                ring(Self::damage(damage::FIRE, 20, 80)), ring(Self::inflict(condition::BURNING, 1, 3)),
                Default::default(),
            ],
        )
    }

    /// Snare: `TRAP`, then its payload, earth damage 10…40 and Crippled 3.
    fn snare() -> Skill {
        let trap = Entry {
            kind: kind::TRAP, target: target::TILE, shape: shape::SINGLE, ..Default::default()
        };
        Self::skill(
            skill_kind::TRAP,
            [trap, Self::damage(damage::EARTH, 10, 40), Self::inflict(condition::CRIPPLED, 3, 3)],
        )
    }

    /// Static Lash: lightning damage 10…60 and its hit's 25 % penetration.
    fn static_lash() -> Skill {
        let pierce = Entry { v0: 25, v12: 25, ..Self::on_foe(kind::HIT_PENETRATION) };
        Self::skill(
            skill_kind::SPELL,
            [Self::damage(damage::LIGHTNING, 10, 60), pierce, Default::default()],
        )
    }

    /// Cleave: an attack skill, `ATTACK_BONUS` 10…30.
    fn cleave() -> Skill {
        let bonus = Entry { v0: 10, v12: 30, ..Self::on_foe(kind::ATTACK_BONUS) };
        Self::skill(skill_kind::ATTACK, [bonus, Default::default(), Default::default()])
    }

    /// Second Wind: `HEAL` 40…140, and a second `HEAL` guarded `BELOW_HALF` (FX-17).
    fn second_wind() -> Skill {
        let heal = Entry { v0: 40, v12: 140, ..Self::on_self(kind::HEAL) };
        let more = Entry { guard: guard::BELOW_HALF, ..heal };
        Self::skill(skill_kind::SKILL, [heal, more, Default::default()])
    }

    /// Venom Coat: `ON_ATTACK_CONDITION` Poison 24 for 12 ticks.
    fn venom_coat() -> Skill {
        let coat = Entry {
            param: condition::POISON, v0: 24, v12: 24, d0: 12, d12: 12,
            ..Self::on_self(kind::ON_ATTACK_CONDITION)
        };
        Self::skill(skill_kind::PREPARATION, [coat, Default::default(), Default::default()])
    }

    /// Every field of an entry at its widest.
    fn entry_max() -> Entry {
        EntryTrait::new(0xFF, 0xFF, -32768, 32767, 43688, 43688, 63, 3, 7, 1, 7, 3)
    }

    fn passive_max() -> Passive {
        PassiveTrait::new(0xFF, 0xFF, 7, 3, -32768, 32767)
    }

    fn caste_max() -> Caste {
        CasteTrait::new(
            0xFF,
            0xFF,
            0xFFFF,
            0xFF,
            0xFF,
            [63, 1, 2, 3, 4, 5, 6, 7, 63],
            WeaponTrait::new(15, 0xFFFF, 15, 15, 15),
            85,
            0xFF,
            [0xFFFF, 2, 3, 0xFFFF],
            15,
            0xFF,
            0xFFFF,
            true,
        )
    }
}

// §2.1: 97 bits, every field at its widest round-trips; each sits at its bit; the empty entry is 0.
#[test]
#[available_gas(l2_gas: 803502)] // ceil(1.05 × 765240 measured)
fn test_entry_round_trip() {
    let top = Fixture::entry_max();
    let bits = top.pack();
    assert(bits < ENTRY_BOUND, '97 bits');
    assert(EntryTrait::unpack(bits) == top, 'top round trip');
    let low = Entry { v0: 32767, v12: -32768, d0: 0, d12: 0, ..top };
    assert(EntryTrait::unpack(low.pack()) == low, 'signed ends');
    let empty: Entry = Default::default();
    assert(empty.pack() == 0 && EntryTrait::unpack(0) == empty, 'empty is 0');
    let at = |entry: Entry| -> u128 {
        entry.pack()
    };
    let e: Entry = Default::default();
    assert(at(Entry { kind: 1, ..e }) == 1, 'kind at 0');
    assert(at(Entry { param: 1, ..e }) == 0x100, 'param at 8');
    assert(at(Entry { v0: 1, ..e }) == 0x10000, 'v0 at 16');
    assert(at(Entry { v0: -1, ..e }) == 0xFFFF0000, 'v0 signed');
    assert(at(Entry { v12: 1, ..e }) == 0x100000000, 'v12 at 32');
    assert(at(Entry { d0: 1, ..e }) == 0x1000000000000, 'd0 at 48');
    assert(at(Entry { d12: 1, ..e }) == 0x10000000000000000, 'd12 at 64');
    assert(at(Entry { charges: 1, ..e }) == 0x100000000000000000000, 'charges at 80');
    assert(at(Entry { target: 1, ..e }) == 0x4000000000000000000000, 'target at 86');
    assert(at(Entry { shape: 1, ..e }) == 0x10000000000000000000000, 'shape at 88');
    assert(at(Entry { filter: 1, ..e }) == 0x80000000000000000000000, 'filter at 91');
    assert(at(Entry { guard: 1, ..e }) == 0x100000000000000000000000, 'guard at 92');
    assert(at(Entry { scope: 1, ..e }) == 0x800000000000000000000000, 'scope at 95');
}

#[test]
#[should_panic(expected: 'entry: charges')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_charges_refused() {
    Entry { charges: 64, ..Default::default() }.pack();
}

#[test]
#[should_panic(expected: 'entry: target')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_target_refused() {
    Entry { target: 4, ..Default::default() }.pack();
}

#[test]
#[should_panic(expected: 'entry: shape')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_shape_refused() {
    Entry { shape: 8, ..Default::default() }.pack();
}

#[test]
#[should_panic(expected: 'entry: filter')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_filter_refused() {
    Entry { filter: 2, ..Default::default() }.pack();
}

#[test]
#[should_panic(expected: 'entry: guard')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_guard_refused() {
    Entry { guard: 8, ..Default::default() }.pack();
}

#[test]
#[should_panic(expected: 'entry: scope')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_scope_refused() {
    Entry { scope: 4, ..Default::default() }.pack();
}

// `MAX_BASE_DURATION` (ENG-01 §3.1): the registry's writer refuses a longer duration.
#[test]
#[should_panic(expected: 'entry: duration')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_duration_refused() {
    Entry { d12: 43689, ..Default::default() }.pack();
}

// §2.2: the line through ranks 0 and 12, truncated toward zero, extrapolated to 15 (FX-0b).
#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_entry_scaling() {
    let rending = Fixture::inflict(condition::BLEEDING, 5, 20);
    assert(rending.value(0) == 5 && rending.value(12) == 20, 'ends');
    assert(rending.value(6) == 12, 'rank 6: 5 + 15 x 6 / 12');
    assert(rending.value(15) == 23, 'rank 15: 5 + 225 / 12');
    let falling = Entry { v0: 0, v12: -13, ..Default::default() };
    assert(falling.value(1) == -1, 'toward zero: -13 / 12');
    assert(falling.value(15) == -16, '-195 / 12');
    let widest = Entry { v0: -32768, v12: 32767, ..Default::default() };
    assert(widest.value(15) == -32768 + 65535 * 15 / 12, 'fits i32');
    let shrinking = Entry { d0: 10, d12: 0, ..Default::default() };
    assert(shrinking.duration(12) == 0 && shrinking.duration(15) == -2, 'duration line');
}

#[test]
#[should_panic(expected: 'entry: rank')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_rank_refused() {
    Fixture::damage(damage::FIRE, 1, 2).value(16);
}

// §3's "class" column, and §7.1's enumerations as frozen ids.
#[test]
#[available_gas(l2_gas: 163254)] // ceil(1.05 × 155480 measured)
fn test_kind_classes_and_ids() {
    let class = |k: u8| -> Option<KindClass> {
        Entry { kind: k, ..Default::default() }.class()
    };
    assert(class(0) == Option::None, 'empty');
    assert(class(kind::DAMAGE) == Option::Some(KindClass::Hit), 'damage');
    assert(class(kind::ATTACK_BONUS) == Option::Some(KindClass::HitModifier), 'bonus');
    assert(class(kind::HIT_PENETRATION) == Option::Some(KindClass::HitModifier), 'hit pen');
    let holding = array![5_u8, 9, 10, 11, 13, 14, 15, 16];
    for k in holding {
        assert(class(k) == Option::Some(KindClass::Holding), 'holding');
    }
    let instant = array![3_u8, 4, 6, 7, 8, 17];
    for k in instant {
        assert(class(k) == Option::Some(KindClass::Instant), 'instant');
    }
    assert(class(kind::TRAP) == Option::Some(KindClass::Placement), 'trap');
    for k in 19..24_u8 {
        assert(class(k) == Option::None, 'after the MVP');
    }
    assert(kind::LAST == 23 && id::FIRST == 40 && id::LAST == 65, 'kinds');
    assert(condition::LAST == 9 && damage::LAST == 9 && skill_kind::LAST == 12, 'enums');
    assert(shape::LAST == 5 && guard::LAST == 4 && scope::ALL == 3 && target::TILE == 3, 'fields');
    assert(weapon::SWORD == 1 && weapon::WAND == 6, 'weapon classes');
    assert(HitClass::Weapon != HitClass::Trap, 'hit classes');
}

// §3's "reads" and bounds: the design's own entries are legal.
#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_entry_legal() {
    Fixture::inflict(condition::BLEEDING, 5, 20).assert_legal();
    Fixture::damage(damage::HOLY, 0, 26213).assert_legal();
    let [coat, _, _] = Fixture::venom_coat().entries;
    coat.assert_legal();
    let oil = Entry { d0: 0, d12: 0, charges: 3, ..coat };
    oil.assert_legal();
    let brace = Entry { v0: 1, v12: 3, d0: 10, d12: 10, ..Fixture::on_self(kind::BLOCK) };
    brace.assert_legal();
    let sidestep = Entry { param: 1, d0: 2, d12: 6, ..Fixture::on_self(kind::EVADE) };
    sidestep.assert_legal();
    let warcry = Entry {
        v0: 10, v12: 20, d0: 5, d12: 11, scope: scope::ALL, ..Fixture::on_self(kind::PENETRATION)
    };
    warcry.assert_legal();
    let drain = Entry { v0: -255, v12: -255, ..Fixture::on_foe(kind::ENERGY) };
    drain.assert_legal();
    let regen = Entry { v0: -10, v12: 6, d0: 5, d12: 5, ..Fixture::on_self(5) };
    regen.assert_legal();
    Fixture::on_foe(kind::INTERRUPT).assert_legal();
    let empty: Entry = Default::default();
    empty.assert_legal();
}

#[test]
#[should_panic(expected: 'entry: value out of bounds')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_value_at_rank_15_refused() {
    // 10 at rank 12 extrapolates to 12 at rank 15: above `REGENERATION`'s +10.
    Entry { v0: 2, v12: 10, d0: 5, d12: 5, ..Fixture::on_self(kind::REGENERATION) }.assert_legal();
}

#[test]
#[should_panic(expected: 'entry: value out of bounds')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_condition_of_zero_ticks_refused() {
    Fixture::inflict(condition::POISON, 0, 5).assert_legal();
}

#[test]
#[should_panic(expected: 'entry: field not read')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_unread_field_refused() {
    // `HEAL` reads no duration.
    Entry { v0: 1, v12: 1, d0: 3, ..Fixture::on_self(kind::HEAL) }.assert_legal();
}

#[test]
#[should_panic(expected: 'entry: param')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_unknown_condition_refused() {
    Fixture::inflict(10, 1, 1).assert_legal();
}

#[test]
#[should_panic(expected: 'entry: neither d nor charges')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_oil_without_time_refused() {
    let [coat, _, _] = Fixture::venom_coat().entries;
    Entry { d0: 0, d12: 0, charges: 0, ..coat }.assert_legal();
}

#[test]
#[should_panic(expected: 'entry: kind after the MVP')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_post_mvp_kind_refused() {
    Fixture::on_self(kind::SUMMON).assert_legal();
}

#[test]
#[should_panic(expected: 'entry: empty with a field')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_empty_with_field_refused() {
    Entry { guard: 1, ..Default::default() }.assert_legal();
}

#[test]
#[should_panic(expected: 'entry: shape')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_shape_zero_refused() {
    Entry { shape: 0, ..Fixture::on_foe(kind::INTERRUPT) }.assert_legal();
}

#[test]
#[should_panic(expected: 'entry: duration')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_entry_negative_duration_at_15_refused() {
    Entry { v0: 1, v12: 1, d0: 10, d12: 0, ..Fixture::on_self(kind::ARMOR) }.assert_legal();
}

// §4: 53 bits; signed range; two in a limb of 106.
#[test]
#[available_gas(l2_gas: 301266)] // ceil(1.05 × 286920 measured)
fn test_passive_round_trip() {
    let top = Fixture::passive_max();
    let bits = top.pack();
    assert(bits < 0x20000000000000, '53 bits');
    assert(PassiveTrait::unpack(bits) == top, 'top round trip');
    let at = |passive: Passive| -> u128 {
        passive.pack()
    };
    let p: Passive = Default::default();
    assert(at(Passive { id: 1, ..p }) == 1, 'id at 0');
    assert(at(Passive { param: 1, ..p }) == 0x100, 'param at 8');
    assert(at(Passive { guard: 1, ..p }) == 0x10000, 'guard at 16');
    assert(at(Passive { scope: 1, ..p }) == 0x80000, 'scope at 19');
    assert(at(Passive { min: 1, ..p }) == 0x200000, 'min at 21');
    assert(at(Passive { max: 1, ..p }) == 0x2000000000, 'max at 37');
    assert(at(Passive { min: -1, ..p }) == 0xFFFF * 0x200000, 'signed min');
    let other = PassiveTrait::new(id::ARMOR, 0, guard::IN_STANCE, 0, -18, 18);
    let pair = PassiveTrait::pack_pair(@top, @other);
    assert(pair < 0x400000000000000000000000000, '106 bits');
    assert(PassiveTrait::unpack_pair(pair) == (top, other), 'pair round trip');
}

#[test]
#[should_panic(expected: 'passive: guard')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_passive_guard_refused() {
    Passive { guard: 8, ..Default::default() }.pack();
}

#[test]
#[should_panic(expected: 'passive: scope')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_passive_scope_refused() {
    Passive { scope: 4, ..Default::default() }.pack();
}

// §4, §7.2: the pipeline's bounds on the passives the snapshot sums.
#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_passive_legal() {
    let damage = PassiveTrait::new(id::DAMAGE_PERCENT, 0, guard::ABOVE_HALF, scope::ALL, 10, 18);
    damage.assert_legal();
    PassiveTrait::new(id::ARMOR, 0, guard::ENCHANTED, 0, -18, 10).assert_legal();
    PassiveTrait::new(id::ARMOR, 0, guard::ALWAYS, 0, -255, 255).assert_legal();
    PassiveTrait::new(id::PENETRATION, 0, 0, scope::WEAPON, 2, 4).assert_legal();
    PassiveTrait::new(id::KNOCKDOWN_FLAT, 0, 0, 0, 1, 1).assert_legal();
    PassiveTrait::new(id::MAX_HEALTH, 0, 0, 0, -75, -75).assert_legal();
    let none: Passive = Default::default();
    none.assert_legal();
}

#[test]
#[should_panic(expected: 'passive: value out of bounds')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_passive_damage_percent_bound_refused() {
    PassiveTrait::new(id::DAMAGE_PERCENT, 0, 0, 0, 10, 19).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: value out of bounds')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_passive_guarded_armor_bound_refused() {
    PassiveTrait::new(id::ARMOR, 0, guard::IN_STANCE, 0, -19, 10).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: guard')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_passive_guard_not_its_refused() {
    PassiveTrait::new(id::DAMAGE_PERCENT, 0, guard::BELOW_HALF, 0, 1, 1).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: scope')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_passive_scope_not_its_refused() {
    PassiveTrait::new(id::LIFE_STEAL_ON_HIT, 0, 0, scope::SPELL, 1, 1).assert_legal();
}

#[test]
#[should_panic(expected: 'passive: id after the MVP')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_passive_post_mvp_refused() {
    PassiveTrait::new(id::CASTE_ARMOR, 0, 0, 0, 1, 1).assert_legal();
}

// §7.2: `SKILL`, 2 parts: the header in part 0's low limb, entries 1–3 in the three others.
#[test]
#[available_gas(l2_gas: 1739115)] // ceil(1.05 × 1656300 measured)
fn test_skill_round_trip() {
    let top = Fixture::entry_max();
    let skill = SkillTrait::new(
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 43688, 43688, 0xFF, 3, true, [top, top, top],
    );
    let packed = skill.pack();
    assert(packed.len() == parts(SKILL).into(), 'parts');
    assert(Record::<Skill>::unpack(packed) == skill, 'top round trip');
    let zero = SkillTrait::new(0, 0, 0, 0, 0, 0, 0, 0, 0, false, [Default::default(); 3]);
    assert(zero.pack() == array![LIVE, LIVE].span(), 'empty is LIVE');
    assert(Record::<Skill>::unpack(zero.pack()) == zero, 'zero round trip');
    // Header bits: kind 16, energy 24, activation 40, recharge 56, target 80, elite 82.
    let header = SkillTrait::new(0, 0, 1, 1, 0, 1, 1, 0, 1, true, [Default::default(); 3]);
    let expected = 0x10000 + 0x1000000 + 0x10000000000 + 0x100000000000000
        + 0x100000000000000000000 + 0x400000000000000000000 + LIVE;
    assert(*header.pack()[0] == expected, 'header bits');
    // Entries: 1 in part 0's high limb, 2 in part 1's low, 3 in its high.
    let one = Entry { kind: 1, ..Default::default() };
    let e: Entry = Default::default();
    let parts = SkillTrait::new(0, 0, 0, 0, 0, 0, 0, 0, 0, false, [one, one, one]).pack();
    assert(*parts[0] == TWO_128 + LIVE && *parts[1] == 1 + TWO_128 + LIVE, 'entry limbs');
    let snare = Fixture::snare();
    assert(Record::<Skill>::unpack(snare.pack()) == snare, 'snare round trip');
    assert(snare.count() == 3 && Fixture::cleave().count() == 1, 'count');
    assert(SkillTrait::new(0, 0, 0, 0, 0, 0, 0, 0, 0, false, [e; 3]).count() == 0, 'none');
}

#[test]
#[should_panic(expected: 'skill: duration')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_skill_recharge_refused() {
    let skill = Fixture::cleave();
    SkillTrait::new(1, 1, 1, 0, 4, 0, 43689, 1, 1, false, skill.entries).pack();
}

#[test]
#[should_panic(expected: 'skill: target')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_skill_target_refused() {
    let skill = Fixture::cleave();
    SkillTrait::new(1, 1, 1, 0, 4, 0, 1, 1, 4, false, skill.entries).pack();
}

// §5.14: design/03's starter skills, as design/19 §8 writes them, are legal carriers.
#[test]
#[available_gas(l2_gas: 1504356)] // ceil(1.05 × 1432720 measured)
fn test_legal_carriers() {
    Fixture::cinder_ring().assert_legal();
    Fixture::snare().assert_legal();
    Fixture::static_lash().assert_legal();
    Fixture::cleave().assert_legal();
    Fixture::second_wind().assert_legal();
    Fixture::venom_coat().assert_legal();
    let skullring = Fixture::skill(
        skill_kind::ATTACK,
        [
            Fixture::inflict(condition::KNOCKED_DOWN, 2, 2), Default::default(),
            Default::default(),
        ],
    );
    skullring.assert_legal();
    let dressing = Fixture::skill(
        skill_kind::SKILL,
        [
            Entry { v0: 30, v12: 120, ..Fixture::on_self(kind::HEAL) },
            Entry { param: condition::BLEEDING, ..Fixture::on_self(kind::CURE) },
            Default::default(),
        ],
    );
    dressing.assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: gap')]
#[available_gas(l2_gas: 215765)] // ceil(1.05 × 205490 measured)
fn test_carrier_gap_refused() {
    let [a, b, _] = Fixture::cinder_ring().entries;
    Fixture::skill(skill_kind::SPELL, [a, Default::default(), b]).assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: two hits')]
#[available_gas(l2_gas: 163800)] // ceil(1.05 × 156000 measured)
fn test_carrier_two_hits_refused() {
    let hit = Fixture::damage(damage::FIRE, 1, 2);
    Fixture::skill(skill_kind::SPELL, [hit, hit, Default::default()]).assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: two hits')]
#[available_gas(l2_gas: 85061)] // ceil(1.05 × 81010 measured)
fn test_carrier_attack_with_damage_refused() {
    let hit = Fixture::damage(damage::SLASHING, 1, 2);
    Fixture::skill(skill_kind::ATTACK, [hit, Default::default(), Default::default()])
        .assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: damage not first')]
#[available_gas(l2_gas: 163506)] // ceil(1.05 × 155720 measured)
fn test_carrier_damage_not_first_refused() {
    let [hit, burn, _] = Fixture::cinder_ring().entries;
    Fixture::skill(skill_kind::SPELL, [burn, hit, Default::default()]).assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: two holding entries')]
#[available_gas(l2_gas: 162803)] // ceil(1.05 × 155050 measured)
fn test_carrier_two_holding_refused() {
    let armor = Entry { v0: 5, v12: 5, d0: 8, d12: 20, ..Fixture::on_self(kind::ARMOR) };
    let move = Entry { d0: 5, d12: 5, ..Fixture::on_self(kind::MOVEMENT) };
    Fixture::skill(skill_kind::ENCHANTMENT, [armor, move, Default::default()]).assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: modifier without hit')]
#[available_gas(l2_gas: 202881)] // ceil(1.05 × 193220 measured)
fn test_carrier_modifier_without_hit_refused() {
    let [_, pierce, _] = Fixture::static_lash().entries;
    Fixture::skill(skill_kind::SPELL, [pierce, Default::default(), Default::default()])
        .assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: modifier set')]
#[available_gas(l2_gas: 218295)] // ceil(1.05 × 207900 measured)
fn test_carrier_modifier_on_another_set_refused() {
    let [hit, pierce, _] = Fixture::static_lash().entries;
    let wide = Entry { shape: shape::RING_1, ..pierce };
    Fixture::skill(skill_kind::SPELL, [hit, wide, Default::default()]).assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: attack bonus')]
#[available_gas(l2_gas: 162992)] // ceil(1.05 × 155230 measured)
fn test_carrier_attack_bonus_in_a_spell_refused() {
    let [bonus, _, _] = Fixture::cleave().entries;
    let hit = Fixture::damage(damage::FIRE, 1, 2);
    Fixture::skill(skill_kind::SPELL, [hit, bonus, Default::default()]).assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: attack entry')]
#[available_gas(l2_gas: 72009)] // ceil(1.05 × 68580 measured)
fn test_carrier_attack_entry_on_self_refused() {
    let heal = Entry { v0: 1, v12: 1, ..Fixture::on_self(kind::HEAL) };
    Fixture::skill(skill_kind::ATTACK, [heal, Default::default(), Default::default()])
        .assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: trap entry')]
#[available_gas(l2_gas: 147399)] // ceil(1.05 × 140380 measured)
fn test_carrier_trap_not_first_refused() {
    let [trap, hit, cripple] = Fixture::snare().entries;
    Fixture::skill(skill_kind::TRAP, [hit, trap, cripple]).assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: trap payload')]
#[available_gas(l2_gas: 210914)] // ceil(1.05 × 200870 measured)
fn test_carrier_trap_payload_on_self_refused() {
    let [trap, hit, _] = Fixture::snare().entries;
    let heal = Entry { v0: 1, v12: 1, ..Fixture::on_self(kind::HEAL) };
    Fixture::skill(skill_kind::TRAP, [trap, hit, heal]).assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: disc 1 not a potion')]
#[available_gas(l2_gas: 101388)] // ceil(1.05 × 96560 measured)
fn test_carrier_disc_1_in_a_skill_refused() {
    let hit = Entry { shape: shape::DISC_1, ..Fixture::damage(damage::FIRE, 1, 2) };
    Fixture::skill(skill_kind::SPELL, [hit, Default::default(), Default::default()])
        .assert_legal();
}

#[test]
#[should_panic(expected: 'carrier: area after the MVP')]
#[available_gas(l2_gas: 84578)] // ceil(1.05 × 80550 measured)
fn test_carrier_disc_2_refused() {
    let hit = Entry { shape: shape::DISC_2, ..Fixture::damage(damage::FIRE, 1, 2) };
    Fixture::skill(skill_kind::SPELL, [hit, Default::default(), Default::default()])
        .assert_legal();
}

#[test]
#[should_panic(expected: 'skill: kind')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_skill_seal_of_capture_refused() {
    Fixture::skill(skill_kind::SEAL_OF_CAPTURE, [Default::default(); 3]).assert_legal();
}

// §7.2: `ITEM`, 1 part; a potion carries one entry, a bomb its range and strength.
#[test]
#[available_gas(l2_gas: 479850)] // ceil(1.05 × 457000 measured)
fn test_item_round_trip() {
    let top = ItemTrait::new(0xFF, 0xFFFF, 0xFF, 0xFFFFFFFF, 0xFF, Fixture::entry_max(), 0xFF, 0xFF);
    let packed = top.pack();
    assert(packed.len() == parts(ITEM).into(), 'parts');
    assert(Record::<Item>::unpack(packed) == top, 'top round trip');
    let e: Entry = Default::default();
    let zero = ItemTrait::new(0, 0, 0, 0, 0, e, 0, 0);
    assert(zero.pack() == array![LIVE].span(), 'empty is LIVE');
    // Bits: region 8, value 32, book index 64; the entry at 128, range 225, strength 233.
    let low = ItemTrait::new(0, 1, 0, 1, 1, e, 0, 0);
    assert(*low.pack()[0] == 0x100 + 0x100000000 + 0x10000000000000000 + LIVE, 'low bits');
    let high = ItemTrait::new(0, 0, 0, 0, 0, Entry { kind: 1, ..e }, 1, 1);
    let two_225: felt252 = TWO_128 * 0x2000000000000000000000000;
    let expected = TWO_128 + two_225 + two_225 * 0x100 + LIVE;
    assert(*high.pack()[0] == expected, 'high bits');
    // A bomb: fire damage on a disc around a tile (FX-18, FX-35).
    let fire = Entry {
        kind: kind::DAMAGE,
        param: damage::FIRE,
        v0: 40,
        v12: 40,
        target: target::TILE,
        shape: shape::DISC_1,
        ..e
    };
    let bomb = ItemTrait::new(class::POTION, 1, 1, 10, 0, fire, 4, 60);
    bomb.assert_legal();
    ItemTrait::new(class::INGREDIENT, 1, 1, 1, 3, e, 0, 0).assert_legal();
}

#[test]
#[should_panic(expected: 'entry: scales')]
#[available_gas(l2_gas: 75254)] // ceil(1.05 × 71670 measured)
fn test_item_scaled_potion_refused() {
    let heal = Entry { v0: 10, v12: 20, ..Fixture::on_self(kind::HEAL) };
    ItemTrait::new(class::POTION, 1, 1, 1, 0, heal, 0, 0).assert_legal();
}

#[test]
#[should_panic(expected: 'item: entry not a potion')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_item_entry_not_a_potion_refused() {
    let heal = Entry { v0: 10, v12: 10, ..Fixture::on_self(kind::HEAL) };
    ItemTrait::new(class::TROPHY, 1, 1, 1, 0, heal, 0, 0).assert_legal();
}

// §4, §7.2: `MODIFIER`, 1 part: slot type low, benefit and cost high.
#[test]
#[available_gas(l2_gas: 191552)] // ceil(1.05 × 182430 measured)
fn test_modifier_round_trip() {
    let top = ModifierTrait::new(0xFF, Fixture::passive_max(), Fixture::passive_max());
    let packed = top.pack();
    assert(packed.len() == parts(MODIFIER).into(), 'parts');
    assert(Record::<Modifier>::unpack(packed) == top, 'top round trip');
    let p: Passive = Default::default();
    let bits = ModifierTrait::new(1, Passive { id: 1, ..p }, Passive { id: 1, ..p }).pack();
    let two_181: felt252 = TWO_128 * 0x20000000000000;
    assert(*bits[0] == 1 + TWO_128 + two_181 + LIVE, 'bits');
    // Life steal with a health regeneration cost (design/15).
    let steal = PassiveTrait::new(id::LIFE_STEAL_ON_HIT, 0, 0, 0, 3, 5);
    let cost = PassiveTrait::new(id::HEALTH_REGEN, 0, 0, 0, -1, -1);
    let modifier = ModifierTrait::new(slot::SUFFIX, steal, cost);
    modifier.assert_legal();
    assert(modifier.has_cost(), 'cost');
    assert(!ModifierTrait::new(slot::PREFIX, steal, p).has_cost(), 'no cost');
}

#[test]
#[should_panic(expected: 'passive: cost not fixed')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_modifier_cost_not_fixed_refused() {
    let steal = PassiveTrait::new(id::LIFE_STEAL_ON_HIT, 0, 0, 0, 3, 5);
    let cost = PassiveTrait::new(id::HEALTH_REGEN, 0, 0, 0, -2, -1);
    ModifierTrait::new(slot::SUFFIX, steal, cost).assert_legal();
}

#[test]
#[should_panic(expected: 'modifier: slot')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_modifier_slot_refused() {
    let steal = PassiveTrait::new(id::LIFE_STEAL_ON_HIT, 0, 0, 0, 3, 5);
    ModifierTrait::new(6, steal, Default::default()).assert_legal();
}

// §7.2: `ARMOR_SET`, 1 part: 5 piece bases low, 2 bonuses high.
#[test]
#[available_gas(l2_gas: 233678)] // ceil(1.05 × 222550 measured)
fn test_armor_set_round_trip() {
    let top = ArmorSetTrait::new(
        [0xFFFF, 2, 3, 4, 0xFFFF], [Fixture::passive_max(), Fixture::passive_max()],
    );
    let packed = top.pack();
    assert(packed.len() == parts(ARMOR_SET).into(), 'parts');
    assert(Record::<ArmorSet>::unpack(packed) == top, 'top round trip');
    let p: Passive = Default::default();
    let bits = ArmorSetTrait::new([0, 0, 0, 0, 1], [p, Passive { id: 1, ..p }]).pack();
    let two_181: felt252 = TWO_128 * 0x20000000000000;
    assert(*bits[0] == 0x10000000000000000 + two_181 + LIVE, 'bits');
    // *Hob-breaker* (design/15): knock-downs +1 tick, then the halving.
    let hob = ArmorSetTrait::new(
        [1, 2, 3, 4, 5],
        [
            PassiveTrait::new(id::KNOCKDOWN_FLAT, 0, 0, 0, 1, 1),
            PassiveTrait::new(id::HALVE_FIRST_HEAVY_HIT, 0, 0, 0, 0, 0),
        ],
    );
    hob.assert_legal();
}

// §7.3: `CASTE`, 2 parts, 243 bits over 4 limbs, no field straddling one.
#[test]
#[available_gas(l2_gas: 648690)] // ceil(1.05 × 617800 measured)
fn test_caste_round_trip() {
    let top = Fixture::caste_max();
    let packed = top.pack();
    assert(packed.len() == parts(CASTE).into(), 'parts');
    assert(Record::<Caste>::unpack(packed) == top, 'top round trip');
    let zero = CasteTrait::new(
        0, 0, 0, 0, 0, [0; 9], Default::default(), 0, 0, [0; 4], 0, 0, 0, false,
    );
    assert(zero.pack() == array![LIVE, LIVE].span(), 'empty is LIVE');
    let one = CasteTrait::new(
        0, 0, 0, 0, 0, [0; 9], WeaponTrait::new(1, 0, 0, 0, 1), 0, 0, [0, 0, 0, 1], 1, 0, 1, true,
    );
    let parts = one.pack();
    // Weapon class at 48, its range at 76, rank at 104, boss at 108; loot table at 182; skill 3
    // at part 1's bit 48.
    let low = 0x1000000000000 + 0x10000000000000000000 + 0x100000000000000000000000000
        + 0x1000000000000000000000000000;
    let two_182: felt252 = TWO_128 * 0x40000000000000;
    assert(*parts[0] == low + two_182 + LIVE, 'part 0 bits');
    assert(*parts[1] == 0x1000000000000 + LIVE, 'part 1 bits');
    // Armor against type 9 at 128 + 48.
    let vs = CasteTrait::new(
        0, 0, 0, 0, 0, [0, 0, 0, 0, 0, 0, 0, 0, 1], Default::default(), 0, 0, [0; 4], 0, 0, 0,
        false,
    );
    assert(*vs.pack()[0] == TWO_128 * 0x1000000000000 + LIVE, 'vs 9 at 176');
    let goblin = CasteTrait::new(
        1,
        1,
        100,
        10,
        40,
        [0; 9],
        WeaponTrait::new(weapon::AXE, 12, damage::SLASHING, 1, 1),
        20,
        2,
        [1, 0, 0, 0],
        6,
        30,
        1,
        false,
    );
    goblin.assert_legal();
}

#[test]
#[should_panic(expected: 'caste: energy above 85')]
#[available_gas(l2_gas: 35963)] // ceil(1.05 × 34250 measured)
fn test_caste_energy_refused() {
    let top = Fixture::caste_max();
    Caste { energy: 86, ..top }.pack();
}

#[test]
#[should_panic(expected: 'caste: armor vs above 63')]
#[available_gas(l2_gas: 128037)] // ceil(1.05 × 121940 measured)
fn test_caste_armor_vs_refused() {
    let top = Fixture::caste_max();
    Caste { armor_vs: [64, 0, 0, 0, 0, 0, 0, 0, 0], ..top }.pack();
}

#[test]
#[should_panic(expected: 'caste: rank')]
#[available_gas(l2_gas: 35963)] // ceil(1.05 × 34250 measured)
fn test_caste_rank_refused() {
    let top = Fixture::caste_max();
    Caste { rank: 16, ..top }.pack();
}

#[test]
#[should_panic(expected: 'caste: weapon field')]
#[available_gas(l2_gas: 53183)] // ceil(1.05 × 50650 measured)
fn test_caste_weapon_refused() {
    let top = Fixture::caste_max();
    Caste { weapon: WeaponTrait::new(16, 0, 0, 0, 0), ..top }.pack();
}

#[test]
#[should_panic(expected: 'caste: health regen')]
#[available_gas(l2_gas: 35963)] // ceil(1.05 × 34250 measured)
fn test_caste_health_regen_refused() {
    let top = Fixture::caste_max();
    Caste {
        tier: 1, health_regen: 21, weapon: WeaponTrait::new(1, 1, 1, 1, 1), ..top,
    }
        .assert_legal();
}

// §7.2: a placed trap's `param`.
#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_placer_round_trip() {
    let member = Placer::Member((7, 7));
    assert(member.param() == 63, 'member bits 0-5');
    assert(PlacerTrait::from_param(63) == member, 'member trip');
    let goblin = Placer::Goblin((8 + 16 * 224 + 9, 3));
    let param = goblin.param();
    assert(param == 0x8000 + 16 * 224 + 9 + 3 * 0x1000, 'goblin bits');
    assert(PlacerTrait::from_param(param) == goblin, 'goblin trip');
    let first = Placer::Goblin((8, 0));
    assert(first.param() == 0x8000 && PlacerTrait::from_param(0x8000) == first, 'first goblin');
}

#[test]
#[should_panic(expected: 'placer: entity')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_placer_member_entity_refused() {
    Placer::Goblin((7, 0)).param();
}

#[test]
#[should_panic(expected: 'placer: slot')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_placer_skill_refused() {
    Placer::Goblin((8, 4)).param();
}

// Two's complement at both ends.
#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_signed_ends() {
    assert(SignedTrait::bits8(-128) == 0x80 && SignedTrait::bits8(127) == 0x7F, 'i8 bits');
    assert(SignedTrait::from8(0x80) == -128 && SignedTrait::from8(0xFF) == -1, 'i8 back');
    assert(SignedTrait::bits16(-32768) == 0x8000 && SignedTrait::bits16(-1) == 0xFFFF, 'i16');
    assert(SignedTrait::from16(0x7FFF) == 32767 && SignedTrait::from16(0x8000) == -32768, 'back');
}
