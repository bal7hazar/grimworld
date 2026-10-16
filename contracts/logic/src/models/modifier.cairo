//! `MODIFIER`: its constructor, its checks and its record (layout: `models::index::Modifier`). A
//! modifier carries two passives, a benefit and a cost (design/15 Q-4, design/19 §4).

use crate::helpers::packing::{P8, PackingTrait};
use crate::types::content::{MODIFIER, Record};
use crate::types::passive::{Passive, PassiveAssert, PassiveTrait, Source, id};
use super::base::slot as base_slot;
pub use super::index::Modifier;

/// Slot types, in the order of `ItemMods`' five slots (ENG-01 §3.3, design/15).
pub mod slot {
    pub const PREFIX: u8 = 1;
    pub const SUFFIX: u8 = 2;
    pub const INSCRIPTION: u8 = 3;
    pub const INSIGNIA: u8 = 4;
    pub const RUNE: u8 = 5;
    pub const LAST: u8 = 5;
}

pub mod errors {
    // The content pipeline's checks (`assert_legal`, `assert_catalogue`).
    pub const SLOT: felt252 = 'modifier: slot';
    pub const NO_BENEFIT: felt252 = 'modifier: no benefit';
    pub const TWICE: felt252 = 'modifier: counted twice';
    pub const QUICK_CAST_SLOTS: felt252 = 'modifier: quick-cast slots';
    pub const DAMAGE_TYPE_SLOTS: felt252 = 'modifier: damage type slots';
    pub const PIECE: felt252 = 'modifier: piece';
    pub const PIECE_HEALTH: felt252 = 'modifier: health above piece';
}

#[generate_trait]
pub impl ModifierImpl of ModifierTrait {
    fn new(slot: u8, benefit: Passive, cost: Passive) -> Modifier {
        Modifier { slot, piece: 0, benefit, cost }
    }

    /// An insignia made for armor `piece` (`base::slot::CHEST` … `FEET`, DS-23).
    fn insignia(piece: u8, benefit: Passive, cost: Passive) -> Modifier {
        Modifier { slot: slot::INSIGNIA, piece, benefit, cost }
    }

    /// The most health an insignia of `piece` adds (design/20 §1.3 row 1, DS-23: 15 on the chest,
    /// 10 on the legs, 5 on the head, the hands and the feet).
    fn insignia_health(piece: u8) -> i32 {
        if piece == base_slot::CHEST {
            15
        } else if piece == base_slot::LEGS {
            10
        } else {
            5
        }
    }

    /// Whether it has a cost (a cost id 0 is none).
    #[inline(always)]
    fn has_cost(self: @Modifier) -> bool {
        *self.cost.id != id::NONE
    }

    /// Whether its benefit or its cost is the passive `id`.
    #[inline(always)]
    fn holds(self: @Modifier, id: u8) -> bool {
        *self.benefit.id == id || *self.cost.id == id
    }

    /// Where its passives are held: its slot type (`slot::PREFIX` … `RUNE`); `None` for any
    /// other value (`ModifierAssert::assert_slot` refuses it).
    fn source(self: @Modifier) -> Option<Source> {
        match *self.slot {
            0 => Option::None,
            1 => Option::Some(Source::Prefix),
            2 => Option::Some(Source::Suffix),
            3 => Option::Some(Source::Inscription),
            4 => Option::Some(Source::Insignia),
            5 => Option::Some(Source::Rune),
            _ => Option::None,
        }
    }
}

#[generate_trait]
pub impl ModifierAssert of ModifierAssertTrait {
    /// A known slot type, 1–5.
    #[inline(always)]
    fn assert_slot(self: @Modifier) {
        assert(*self.slot >= slot::PREFIX && *self.slot <= slot::LAST, errors::SLOT);
    }

    /// The content pipeline's checks of one modifier: a known slot type; a benefit, and a fixed
    /// cost or none, each legal and allowed on that slot type (`PassiveTrait::allows`,
    /// design/19 §7.2), the cost included; one slot being one source, together they add to each
    /// sum §7.2 bounds by counting sources no more than one passive may
    /// (`PassiveAssert::assert_contributions`, per guard and hit class), within design/20's
    /// per-source bounds (`PassiveAssert::assert_source_bounds`, DS-1), and they do not name two
    /// things a single-valued field cannot keep (`PassiveTrait::conflicts`).
    fn assert_legal(self: @Modifier) {
        self.assert_slot();
        let source = self.source().unwrap();
        assert(*self.benefit.id != id::NONE, errors::NO_BENEFIT);
        self.benefit.assert_source(source);
        self.cost.assert_source(source);
        self.cost.assert_fixed();
        assert(!self.benefit.conflicts(self.cost), errors::TWICE);
        let passives = array![*self.benefit, *self.cost].span();
        PassiveAssert::assert_contributions(passives);
        PassiveAssert::assert_source_bounds(passives, source);
        self.assert_piece();
    }

    /// DS-23 (D-160): an insignia names its armor piece, and its health (each passive and their
    /// sum) is within the piece's bound, 15 / 10 / 5; any other slot type names none.
    fn assert_piece(self: @Modifier) {
        let piece = *self.piece;
        if *self.slot != slot::INSIGNIA {
            assert(piece == 0, errors::PIECE);
            return;
        }
        assert(piece >= base_slot::CHEST && piece <= base_slot::FEET, errors::PIECE);
        let bound = ModifierTrait::insignia_health(piece);
        let mut sum: i32 = 0;
        for passive in array![*self.benefit, *self.cost] {
            if passive.id == id::MAX_HEALTH {
                let value: i32 = passive.max.into();
                assert(value <= bound, errors::PIECE_HEALTH);
                sum += value;
            }
        }
        assert(sum <= bound, errors::PIECE_HEALTH);
    }

    /// The content pipeline's checks across every `MODIFIER` of the content, each legal: "the
    /// pipeline gives [`QUICK_CAST_EVERY_N`, `DAMAGE_TYPE`] one slot type" (design/19 §4,
    /// §7.2), so all the modifiers holding one of them share a slot type. design/20 §1.8 (D-160)
    /// names them: the inscription for quick cast, the prefix for the damage type, which
    /// `PassiveTrait::allows` enforces on each modifier; the shared-slot check stays as a guard.
    fn assert_catalogue(modifiers: Span<Modifier>) {
        let mut quick_cast: u8 = 0;
        let mut damage_type: u8 = 0;
        for modifier in modifiers {
            modifier.assert_legal();
            let slot = *modifier.slot;
            if modifier.holds(id::QUICK_CAST_EVERY_N) {
                assert(quick_cast == 0 || quick_cast == slot, errors::QUICK_CAST_SLOTS);
                quick_cast = slot;
            }
            if modifier.holds(id::DAMAGE_TYPE) {
                assert(damage_type == 0 || damage_type == slot, errors::DAMAGE_TYPE_SLOTS);
                damage_type = slot;
            }
        }
    }
}

pub impl ModifierRecord of Record<Modifier> {
    const KIND: u8 = MODIFIER;

    fn pack(self: @Modifier) -> Span<felt252> {
        let low: u128 = (*self.slot).into() + (*self.piece).into() * P8;
        array![PackingTrait::join(low, PassiveTrait::pack_pair(self.benefit, self.cost))].span()
    }

    fn unpack(parts: Span<felt252>) -> Modifier {
        let (low, high) = PackingTrait::split(*parts[0]);
        let (benefit, cost) = PassiveTrait::unpack_pair(high);
        let (piece, slot) = DivRem::div_rem(low, P8.try_into().unwrap());
        Modifier { slot: slot.try_into().unwrap(), piece: piece.try_into().unwrap(), benefit, cost }
    }
}

/// The record's unit tests (CBT-01 and its fix loops, design/19 §4 and §7.2; design/20 §6 test
/// 1, D-160; AUD-182): it round-trips, each slot type holds only the passives design/19 and
/// design/20 allow, an insignia names its piece, and a benefit and a cost are refused when they add
/// to one counted sum beyond the source's bound.
#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use crate::models::armor_set::ArmorSetTrait;
    use crate::models::base::slot as base_slot;
    use crate::types::combat::{condition, damage, weapon};
    use crate::types::content::{KindTrait, MODIFIER, Record};
    use crate::types::effect::{guard, scope};
    use crate::types::passive::{MAX_DAMAGE_PERCENT, Passive, PassiveTrait, id};
    use super::{Modifier, ModifierAssert, ModifierTrait, slot};

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    /// Attribute ids of the fixtures (content's global ids, D-157 A): the primary first.
    const PRIMARY: u8 = 13;

    /// The passives these tests start from.
    #[generate_trait]
    impl FixtureImpl of Fixture {
        fn passive_max() -> Passive {
            PassiveTrait::new(0xFF, 0xFF, 7, 3, -32768, 32767)
        }

        fn passive(id: u8, param: u8, value: i16) -> Passive {
            PassiveTrait::new(id, param, 0, 0, value, value)
        }

        /// `DAMAGE_PERCENT +18`, the widest.
        fn widest_damage() -> Passive {
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
                ModifierTrait::insignia(base_slot::CHEST, benefit, Default::default())
                    .assert_legal();
            } else {
                ModifierTrait::new(slot, benefit, Default::default()).assert_legal();
            }
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
    }

    fn passive(id: u8, param: u8, value: i16) -> Passive {
        PassiveTrait::new(id, param, 0, 0, value, value)
    }

    // §4, §7.2: `MODIFIER`, 1 part: slot type low, benefit and cost high.
    #[test]
    #[available_gas(l2_gas: 345734)] // ceil(1.05 × 329270 measured)
    fn test_modifier_round_trip() {
        let top = ModifierTrait::new(0xFF, Fixture::passive_max(), Fixture::passive_max());
        let packed = top.pack();
        assert(packed.len() == KindTrait::parts(MODIFIER).into(), 'parts');
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
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_modifier_cost_not_fixed_refused() {
        let steal = PassiveTrait::new(id::LIFE_STEAL_ON_HIT, 0, 0, 0, 3, 5);
        let cost = PassiveTrait::new(id::HEALTH_REGEN, 0, 0, 0, -2, -1);
        ModifierTrait::new(slot::SUFFIX, steal, cost).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'modifier: slot')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_modifier_slot_refused() {
        let steal = PassiveTrait::new(id::LIFE_STEAL_ON_HIT, 0, 0, 0, 3, 5);
        ModifierTrait::new(6, steal, Default::default()).assert_legal();
    }

    // CBT-1: through the containing record.
    #[test]
    #[should_panic(expected: 'passive: param')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_modifier_armor_vs_type_255_refused() {
        Fixture::on(slot::SUFFIX, Fixture::passive(id::ARMOR_VS, 255, 5));
    }

    // CBT-2: design/19 §7.2's sources. The audit's case: an insignia giving `DAMAGE_PERCENT +18`.
    #[test]
    #[should_panic(expected: 'passive: not on this source')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_damage_percent_on_insignia_refused() {
        Fixture::on(slot::INSIGNIA, Fixture::widest_damage());
    }

    #[test]
    #[should_panic(expected: 'passive: not on this source')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_damage_percent_on_rune_refused() {
        Fixture::on(slot::RUNE, Fixture::widest_damage());
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
    fn test_condition_duration_on_suffix_refused() {
        Fixture::on(
            slot::SUFFIX, Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 33),
        );
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
        ModifierTrait::new(slot::INSCRIPTION, Fixture::widest_damage(), drawback).assert_legal();
    }

    // CBT-2: the sources design/19 allows are accepted.
    #[test]
    #[available_gas(l2_gas: 1529357)] // ceil(1.05 × 1456530 measured)
    fn test_sources_accepted() {
        Fixture::on(slot::PREFIX, Fixture::widest_damage());
        Fixture::on(slot::SUFFIX, Fixture::widest_damage());
        Fixture::on(slot::INSCRIPTION, Fixture::widest_damage());
        Fixture::on(slot::PREFIX, Fixture::passive(id::PENETRATION, 0, 4));
        Fixture::on(slot::INSIGNIA, Fixture::stance_armor());
        Fixture::on(slot::INSCRIPTION, Fixture::quick_cast());
        Fixture::on(
            slot::PREFIX, Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 33),
        );
        Fixture::on(slot::PREFIX, Fixture::passive(id::DAMAGE_TYPE, 4, 0));
        Fixture::on(slot::RUNE, Fixture::passive(id::ARMOR, 0, 5));
        Fixture::on(slot::RUNE, Fixture::passive(id::ATTRIBUTE, 3, 2));
        // "+15 % damage, −5 energy" (design/15): a counted benefit with an uncounted cost.
        let energy = Fixture::passive(id::MAX_ENERGY, 0, -5);
        ModifierTrait::new(slot::INSCRIPTION, Fixture::widest_damage(), energy).assert_legal();
        // Hob-breaker: the stance insignia's armor as a bonus, knock-down +1 a bonus (DS-5: ≤ 1).
        let one = Fixture::passive(id::KNOCKDOWN_FLAT, 0, 1);
        ArmorSetTrait::new([1, 2, 3, 4, 5], [one, one]).assert_legal();
        ArmorSetTrait::new([1, 2, 3, 4, 5], [Fixture::widest_damage(), Fixture::stance_armor()])
            .assert_legal();
    }

    // CBT-8: a modifier's benefit and cost are refused only when they add to one counted sum
    // (statistic, guard, scope). The audit's insignia: `ARMOR +10 IN_STANCE`, `ARMOR −5
    // ENCHANTED`.
    #[test]
    #[available_gas(l2_gas: 1002509)] // ceil(1.05 × 954770 measured)
    fn test_separate_sums_accepted() {
        let insignia = Fixture::modifier(
            slot::INSIGNIA,
            Fixture::armor(guard::IN_STANCE, 10),
            Fixture::armor(guard::ENCHANTED, -5),
        );
        insignia.assert_legal();
        // Unguarded and guarded armor are separate sums.
        Fixture::modifier(
            slot::INSIGNIA, Fixture::armor(guard::IN_STANCE, 10), Fixture::armor(0, -5),
        )
            .assert_legal();
        // Damage: another scope, or another guard.
        let weapon = Fixture::damage(guard::ALWAYS, scope::WEAPON, 10);
        Fixture::modifier(slot::PREFIX, weapon, Fixture::damage(guard::ALWAYS, scope::SPELL, -5))
            .assert_legal();
        Fixture::modifier(
            slot::PREFIX, weapon, Fixture::damage(guard::ABOVE_HALF, scope::WEAPON, -5),
        )
            .assert_legal();
        Fixture::modifier(
            slot::SUFFIX,
            Fixture::penetration(scope::WEAPON, 4),
            Fixture::penetration(scope::SPELL, 1),
        )
            .assert_legal();
        // Armor against two types is two sums; one type twice within its per-source bound, 3 + 4
        // (design/20 row 7: ≤ 7 a source).
        let vs = Fixture::passive(id::ARMOR_VS, 1, 7);
        Fixture::modifier(slot::RUNE, vs, Fixture::passive(id::ARMOR_VS, 2, 7)).assert_legal();
        Fixture::modifier(
            slot::RUNE, Fixture::passive(id::ARMOR_VS, 1, 3), Fixture::passive(id::ARMOR_VS, 1, 4),
        )
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: source adds too much')]
    #[available_gas(l2_gas: 41969)] // ceil(1.05 × 39970 measured)
    fn test_damage_all_and_weapon_same_guard_refused() {
        // 10 + 10 on a plain weapon hit (and on an attack skill's): 20 > 18.
        let all = Fixture::damage(guard::ALWAYS, scope::ALL, 10);
        Fixture::modifier(slot::PREFIX, all, Fixture::damage(guard::ALWAYS, scope::WEAPON, 10))
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: source adds too much')]
    #[available_gas(l2_gas: 121947)] // ceil(1.05 × 116140 measured)
    fn test_penetration_all_and_spell_refused() {
        // 30 + 10 on a spell's hit: 40 > 36.
        Fixture::modifier(
            slot::SUFFIX,
            Fixture::penetration(scope::ALL, 30),
            Fixture::penetration(scope::SPELL, 10),
        )
            .assert_legal();
    }

    // CBT-8 (fix loop 3): two unguarded `ARMOR` passives in one slot are accepted: §7.2 bounds the
    // unguarded armor by its total (±9,995, F-21), not one passive per slot; the audit's rune, +5
    // and −2.
    #[test]
    #[available_gas(l2_gas: 400638)] // ceil(1.05 × 381560 measured)
    fn test_unguarded_armor_twice_accepted() {
        Fixture::modifier(slot::RUNE, Fixture::armor(0, 5), Fixture::armor(0, -2)).assert_legal();
        Fixture::modifier(slot::RUNE, Fixture::armor(0, 255), Fixture::armor(0, 255))
            .assert_legal();
        // Within the bound, one source's two passives of a counted sum pass too.
        Fixture::modifier(
            slot::INSIGNIA,
            Fixture::armor(guard::IN_STANCE, 10),
            Fixture::armor(guard::IN_STANCE, -2),
        )
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: source adds too much')]
    #[available_gas(l2_gas: 120908)] // ceil(1.05 × 115150 measured)
    fn test_stance_armor_twice_refused() {
        // 10 + 10 in a stance: 20 > 18.
        Fixture::modifier(
            slot::INSIGNIA,
            Fixture::armor(guard::IN_STANCE, 10),
            Fixture::armor(guard::IN_STANCE, 10),
        )
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'modifier: counted twice')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_two_conditions_on_one_prefix_refused() {
        Fixture::modifier(
            slot::PREFIX,
            Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 33),
            Fixture::passive(id::CONDITION_DURATION, condition::POISON, 10),
        )
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: per-source bound')]
    #[available_gas(l2_gas: 138779)] // ceil(1.05 × 132170 measured)
    fn test_same_condition_above_33_refused() {
        Fixture::modifier(
            slot::PREFIX,
            Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 33),
            Fixture::passive(id::CONDITION_DURATION, condition::BLEEDING, 10),
        )
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'modifier: counted twice')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_two_quick_casts_on_one_slot_refused() {
        let quick = Fixture::passive(id::QUICK_CAST_EVERY_N, 3, 5);
        Fixture::modifier(slot::INSCRIPTION, quick, Fixture::passive(id::QUICK_CAST_EVERY_N, 4, 5))
            .assert_legal();
    }

    // AUD-182-4 (design/20 §1.8, D-157 B and C, D-160): quick cast is held on inscriptions, the
    // damage type on prefixes; there, a catalogue of several is accepted.
    #[test]
    #[available_gas(l2_gas: 727157)] // ceil(1.05 × 692530 measured)
    fn test_decided_slot_types_accepted() {
        let none: Passive = Default::default();
        ModifierAssert::assert_catalogue(
            array![
                Fixture::modifier(
                    slot::INSCRIPTION, Fixture::passive(id::QUICK_CAST_EVERY_N, 3, 5), none,
                ),
                Fixture::modifier(
                    slot::INSCRIPTION, Fixture::passive(id::QUICK_CAST_EVERY_N, 7, 4), none,
                ),
                Fixture::modifier(slot::PREFIX, Fixture::passive(id::DAMAGE_TYPE, 4, 0), none),
                Fixture::modifier(slot::PREFIX, Fixture::passive(id::DAMAGE_TYPE, 5, 0), none),
            ]
                .span(),
        );
    }

    #[test]
    #[should_panic(expected: 'passive: not on this source')]
    #[available_gas(l2_gas: 99750)] // ceil(1.05 × 95000 measured)
    fn test_damage_type_suffix_catalogue_refused() {
        let none: Passive = Default::default();
        ModifierAssert::assert_catalogue(
            array![Fixture::modifier(slot::SUFFIX, Fixture::passive(id::DAMAGE_TYPE, 5, 0), none)]
                .span(),
        );
    }

    #[test]
    #[should_panic(expected: 'passive: not on this source')]
    #[available_gas(l2_gas: 99750)] // ceil(1.05 × 95000 measured)
    fn test_quick_cast_on_a_suffix_refused() {
        let none: Passive = Default::default();
        ModifierAssert::assert_catalogue(
            array![
                Fixture::modifier(
                    slot::SUFFIX, Fixture::passive(id::QUICK_CAST_EVERY_N, 3, 5), none,
                ),
            ]
                .span(),
        );
    }

    #[test]
    #[should_panic(expected: 'passive: not on this source')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_quick_cast_on_an_armor_slot_refused() {
        Fixture::modifier(
            slot::INSIGNIA, Fixture::passive(id::QUICK_CAST_EVERY_N, 3, 5), Default::default(),
        )
            .assert_legal();
    }

    // CBT-6: the slot type is checked by `ModifierAssert`; `source` only maps it.
    #[test]
    #[should_panic(expected: 'modifier: slot')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_slot_0_refused() {
        Fixture::modifier(0, Fixture::armor(0, 5), Default::default()).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'modifier: slot')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_slot_6_refused() {
        Fixture::modifier(6, Fixture::armor(0, 5), Default::default()).assert_legal();
    }

    #[test]
    #[available_gas(l2_gas: 6311)] // ceil(1.05 × 6010 measured)
    fn test_source_maps_slots() {
        assert(
            Fixture::modifier(6, Default::default(), Default::default()).source().is_none(), '6',
        );
        assert(
            Fixture::modifier(0, Default::default(), Default::default()).source().is_none(), '0',
        );
        assert(
            Fixture::modifier(slot::RUNE, Default::default(), Default::default())
                .source()
                .is_some(),
            '5',
        );
    }

    // CBT-2: the audit's case, `PENETRATION(WEAPON, 36)` and `PENETRATION(ATTACK_SKILL, 36)` in one
    // modifier: 72 on an attack skill's hit, refused in both orderings.
    #[test]
    #[should_panic(expected: 'passive: source adds too much')]
    #[available_gas(l2_gas: 91844)] // ceil(1.05 × 87470 measured)
    fn test_penetration_weapon_and_attack_skill_refused() {
        Fixture::modifier(
            slot::PREFIX,
            Fixture::penetration(scope::WEAPON, 36),
            Fixture::penetration(scope::ATTACK_SKILL, 36),
        )
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: source adds too much')]
    #[available_gas(l2_gas: 93503)] // ceil(1.05 × 89050 measured)
    fn test_penetration_attack_skill_and_weapon_refused() {
        Fixture::modifier(
            slot::SUFFIX,
            Fixture::penetration(scope::ATTACK_SKILL, 36),
            Fixture::penetration(scope::WEAPON, 36),
        )
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'passive: source adds too much')]
    #[available_gas(l2_gas: 74928)] // ceil(1.05 × 71360 measured)
    fn test_damage_weapon_and_attack_skill_over_18_refused() {
        Fixture::modifier(
            slot::INSCRIPTION,
            Fixture::damage(guard::ALWAYS, scope::WEAPON, 18),
            Fixture::damage(guard::ALWAYS, scope::ATTACK_SKILL, 1),
        )
            .assert_legal();
    }

    #[test]
    #[available_gas(l2_gas: 421691)] // ceil(1.05 × 401610 measured)
    fn test_scope_overlap_within_bound_accepted() {
        // 10 − 5 on an attack skill's hit; 18 and 18 on weapon and spell hits, which no class
        // adds.
        Fixture::modifier(
            slot::PREFIX,
            Fixture::damage(guard::ALWAYS, scope::WEAPON, 10),
            Fixture::damage(guard::ALWAYS, scope::ATTACK_SKILL, -5),
        )
            .assert_legal();
        Fixture::modifier(
            slot::PREFIX,
            Fixture::damage(guard::ALWAYS, scope::WEAPON, 18),
            Fixture::damage(guard::ALWAYS, scope::SPELL, 18),
        )
            .assert_legal();
        Fixture::modifier(
            slot::SUFFIX,
            Fixture::penetration(scope::WEAPON, 18),
            Fixture::penetration(scope::ATTACK_SKILL, 18),
        )
            .assert_legal();
    }

    // COST-2, the record (DS-23): an insignia names its piece; its health is within the piece's
    // bound;
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

    // AUD-182-2: the audit's rune, a fixed −32,717 health benefit and a +32,767 cost (their sum
    // +50 within the source's bound), is refused: each passive lies within −75…+50.
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
            slot::RUNE,
            passive(id::ATTRIBUTE, PRIMARY, 32767),
            passive(id::ATTRIBUTE, PRIMARY, -32764),
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
}
