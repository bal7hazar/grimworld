//! `SKILL`: its constructor, its checks and its record (layout: `models::index::Skill`).

use crate::helpers::duration::MAX_BASE_DURATION;
use crate::helpers::packing::{P16, P24, P32, P40, P56, P72, P8, P80, PackingTrait};
use crate::types::combat::skill_kind;
use crate::types::content::{Record, SKILL};
use crate::types::effect::{Carrier, Entry, EntryAssert, EntryTrait};
pub use super::index::Skill;

const P82: u128 = 0x400000000000000000000;

pub mod errors {
    pub const TARGET: felt252 = 'skill: target';
    pub const DURATION: felt252 = 'skill: duration';
    // The content pipeline's checks (`assert_legal`).
    pub const KIND: felt252 = 'skill: kind';
}

#[generate_trait]
pub impl SkillImpl of SkillTrait {
    fn new(
        profession: u8,
        attribute: u8,
        kind: u8,
        energy: u8,
        adrenaline: u8,
        activation: u16,
        recharge: u16,
        range: u8,
        target: u8,
        elite: bool,
        entries: [Entry; 3],
    ) -> Skill {
        Skill {
            profession,
            attribute,
            kind,
            energy,
            adrenaline,
            activation,
            recharge,
            range,
            target,
            elite,
            entries,
        }
    }

    /// An attack skill: its action is a weapon hit carrying it (design/19 §3.4).
    #[inline(always)]
    fn is_attack(self: @Skill) -> bool {
        *self.kind == skill_kind::ATTACK
    }

    /// `(profession, elite)` of a record's part 0, its entries left packed: what `set_build`
    /// checks of each skill on the bar. The header is 83 bits: the quotient by 2^82 is the elite
    /// bit.
    fn profile(part: felt252) -> (u8, bool) {
        let (header, _) = PackingTrait::split(part);
        let (elite, rest) = DivRem::div_rem(header, P82.try_into().unwrap());
        let (_, profession) = DivRem::div_rem(rest, P8.try_into().unwrap());
        (profession.try_into().unwrap(), elite != 0)
    }

    /// `(attribute, kind)` of a record's part 0, header bits 8–15 and 16–23: what the loadout
    /// reads of each bar skill (WPN-01: `Loadout.bar_attributes`, `bar_attacks`).
    fn attribute_kind(part: felt252) -> (u8, u8) {
        let (header, _) = PackingTrait::split(part);
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let (header, _) = DivRem::div_rem(header, s8);
        let (header, attribute) = DivRem::div_rem(header, s8);
        let (_, kind) = DivRem::div_rem(header, s8);
        (attribute.try_into().unwrap(), kind.try_into().unwrap())
    }

    /// Its entry count: the index of the last non-empty entry, 0 to 3 (design/19 §2.1).
    fn count(self: @Skill) -> u8 {
        let [a, b, c] = *self.entries;
        if !c.is_empty() {
            3
        } else if !b.is_empty() {
            2
        } else if !a.is_empty() {
            1
        } else {
            0
        }
    }
}

#[generate_trait]
pub impl SkillAssert of SkillAssertTrait {
    /// The header fits its layout: target 2 bits; activation and recharge at most
    /// `MAX_BASE_DURATION` (the registry's writer refuses more, ENG-01 §3.1).
    #[inline(always)]
    fn assert_valid(self: @Skill) {
        assert(*self.target < 4, errors::TARGET);
        let max: u32 = MAX_BASE_DURATION;
        assert(
            (*self.activation).into() <= max && (*self.recharge).into() <= max, errors::DURATION,
        );
    }

    /// The content pipeline's checks (design/19 §5.14, X-1): a kind of the MVP (the Seal of
    /// Capture is deferred, FX-26) and a legal carrier.
    fn assert_legal(self: @Skill) {
        self.assert_valid();
        assert(*self.kind >= skill_kind::ATTACK && *self.kind <= skill_kind::SKILL, errors::KIND);
        let carrier = if self.is_attack() {
            Carrier::Attack
        } else {
            Carrier::Skill
        };
        let [a, b, c] = *self.entries;
        EntryAssert::assert_carrier(array![a, b, c].span(), carrier);
    }
}

pub impl SkillRecord of Record<Skill> {
    const KIND: u8 = SKILL;

    fn pack(self: @Skill) -> Span<felt252> {
        self.assert_valid();
        let header: u128 = (*self.profession).into()
            + (*self.attribute).into() * P8
            + (*self.kind).into() * P16
            + (*self.energy).into() * P24
            + (*self.adrenaline).into() * P32
            + (*self.activation).into() * P40
            + (*self.recharge).into() * P56
            + (*self.range).into() * P72
            + (*self.target).into() * P80
            + if *self.elite {
                P82
            } else {
                0
            };
        let [a, b, c] = self.entries;
        array![PackingTrait::join(header, a.pack()), PackingTrait::join(b.pack(), c.pack())].span()
    }

    fn unpack(parts: Span<felt252>) -> Skill {
        let (header, a) = PackingTrait::split(*parts[0]);
        let (b, c) = PackingTrait::split(*parts[1]);
        let s8: NonZero<u128> = P8.try_into().unwrap();
        let s16: NonZero<u128> = P16.try_into().unwrap();
        let (header, profession) = DivRem::div_rem(header, s8);
        let (header, attribute) = DivRem::div_rem(header, s8);
        let (header, kind) = DivRem::div_rem(header, s8);
        let (header, energy) = DivRem::div_rem(header, s8);
        let (header, adrenaline) = DivRem::div_rem(header, s8);
        let (header, activation) = DivRem::div_rem(header, s16);
        let (header, recharge) = DivRem::div_rem(header, s16);
        let (header, range) = DivRem::div_rem(header, s8);
        let (elite, target) = DivRem::div_rem(header, 4);
        Skill {
            profession: profession.try_into().unwrap(),
            attribute: attribute.try_into().unwrap(),
            kind: kind.try_into().unwrap(),
            energy: energy.try_into().unwrap(),
            adrenaline: adrenaline.try_into().unwrap(),
            activation: activation.try_into().unwrap(),
            recharge: recharge.try_into().unwrap(),
            range: range.try_into().unwrap(),
            target: target.try_into().unwrap(),
            elite: elite != 0,
            entries: [EntryTrait::unpack(a), EntryTrait::unpack(b), EntryTrait::unpack(c)],
        }
    }
}

/// The record's unit tests (CBT-01, design/19 §7.2 and §5.14): it round-trips at its bounds,
/// design/03's starter skills are legal carriers, and each illegal combination of entries is
/// refused (CBT-3's attack modifiers included); the readers of part 0 that `set_build` uses
/// (CBT-08a).
#[cfg(test)]
mod tests {
    use crate::helpers::packing::LIVE;
    use crate::models::item::{ItemAssert, ItemRecord, ItemTrait, class, class as item_class};
    use crate::types::combat::{condition, damage, skill_kind};
    use crate::types::content::{KindTrait, Record, SKILL};
    use crate::types::effect::{Entry, EntryAssert, EntryTrait, filter, guard, kind, shape, target};
    use super::{Skill, SkillAssert, SkillRecord, SkillTrait};

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

        /// Under `ALLIES`: the caster is its own ally, and under `FOES` a `SELF` entry takes nobody
        /// (R-45).
        fn on_self(kind: u8) -> Entry {
            Entry {
                kind,
                target: target::SELF,
                shape: shape::SINGLE,
                filter: filter::ALLIES,
                ..Default::default(),
            }
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
                    ring(Self::damage(damage::FIRE, 20, 80)),
                    ring(Self::inflict(condition::BURNING, 1, 3)), Default::default(),
                ],
            )
        }

        /// Snare: `TRAP`, then its payload, earth damage 10…40 and Crippled 3.
        fn snare() -> Skill {
            let trap = Entry {
                kind: kind::TRAP, target: target::TILE, shape: shape::SINGLE, ..Default::default(),
            };
            Self::skill(
                skill_kind::TRAP,
                [
                    trap, Self::damage(damage::EARTH, 10, 40),
                    Self::inflict(condition::CRIPPLED, 3, 3),
                ],
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
                param: condition::POISON,
                v0: 24,
                v12: 24,
                d0: 12,
                d12: 12,
                ..Self::on_self(kind::ON_ATTACK_CONDITION),
            };
            Self::skill(skill_kind::PREPARATION, [coat, Default::default(), Default::default()])
        }

        /// Every field of an entry at its widest.
        fn entry_max() -> Entry {
            EntryTrait::new(0xFF, 0xFF, -32768, 32767, 43688, 43688, 63, 3, 7, 1, 7, 3)
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
                kind,
                v0: 1,
                v12: 1,
                target: target::FOE,
                shape: shape::SINGLE,
                ..Default::default(),
            }
        }
    }

    // §7.2: `SKILL`, 2 parts: the header in part 0's low limb, entries 1–3 in the three others.
    #[test]
    #[available_gas(l2_gas: 1728626)] // ceil(1.05 × 1646310 measured)
    fn test_skill_round_trip() {
        let top = Fixture::entry_max();
        let skill = SkillTrait::new(
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 43688, 43688, 0xFF, 3, true, [top, top, top],
        );
        let packed = skill.pack();
        assert(packed.len() == KindTrait::parts(SKILL).into(), 'parts');
        assert(Record::<Skill>::unpack(packed) == skill, 'top round trip');
        let zero = SkillTrait::new(0, 0, 0, 0, 0, 0, 0, 0, 0, false, [Default::default(); 3]);
        assert(zero.pack() == array![LIVE, LIVE].span(), 'empty is LIVE');
        assert(Record::<Skill>::unpack(zero.pack()) == zero, 'zero round trip');
        // Header bits: kind 16, energy 24, activation 40, recharge 56, target 80, elite 82.
        let header = SkillTrait::new(0, 0, 1, 1, 0, 1, 1, 0, 1, true, [Default::default(); 3]);
        let expected = 0x10000
            + 0x1000000
            + 0x10000000000
            + 0x100000000000000
            + 0x100000000000000000000
            + 0x400000000000000000000
            + LIVE;
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
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_skill_recharge_refused() {
        let skill = Fixture::cleave();
        SkillTrait::new(1, 1, 1, 0, 4, 0, 43689, 1, 1, false, skill.entries).pack();
    }

    #[test]
    #[should_panic(expected: 'skill: target')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_skill_target_refused() {
        let skill = Fixture::cleave();
        SkillTrait::new(1, 1, 1, 0, 4, 0, 1, 1, 4, false, skill.entries).pack();
    }

    // §5.14: design/03's starter skills, as design/19 §8 writes them, are legal carriers.
    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 1759296)] // ceil(1.05 × 1675520 measured)
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
    // gas: raised, CARRIER-02: assert_carrier's R-45 check
    #[available_gas(l2_gas: 253596)] // ceil(1.05 × 241520 measured)
    fn test_carrier_gap_refused() {
        let [a, b, _] = Fixture::cinder_ring().entries;
        Fixture::skill(skill_kind::SPELL, [a, Default::default(), b]).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'carrier: two hits')]
    // gas: raised, CARRIER-01: assert_carrier's R-44 check
    #[available_gas(l2_gas: 186858)] // ceil(1.05 × 177960 measured)
    fn test_carrier_two_hits_refused() {
        let hit = Fixture::damage(damage::FIRE, 1, 2);
        Fixture::skill(skill_kind::SPELL, [hit, hit, Default::default()]).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'carrier: two hits')]
    // gas: raised, CARRIER-01: assert_carrier's R-44 check
    #[available_gas(l2_gas: 93009)] // ceil(1.05 × 88580 measured)
    fn test_carrier_attack_with_damage_refused() {
        let hit = Fixture::damage(damage::SLASHING, 1, 2);
        Fixture::skill(skill_kind::ATTACK, [hit, Default::default(), Default::default()])
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'carrier: damage not first')]
    // gas: raised, CARRIER-01: assert_carrier's R-44 check
    #[available_gas(l2_gas: 187457)] // ceil(1.05 × 178530 measured)
    fn test_carrier_damage_not_first_refused() {
        let [hit, burn, _] = Fixture::cinder_ring().entries;
        Fixture::skill(skill_kind::SPELL, [burn, hit, Default::default()]).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'carrier: two holding entries')]
    // gas: raised, CARRIER-01: assert_carrier's R-44 check
    #[available_gas(l2_gas: 186753)] // ceil(1.05 × 177860 measured)
    fn test_carrier_two_holding_refused() {
        let armor = Entry { v0: 5, v12: 5, d0: 8, d12: 20, ..Fixture::on_self(kind::ARMOR) };
        let move = Entry { d0: 5, d12: 5, ..Fixture::on_self(kind::MOVEMENT) };
        Fixture::skill(skill_kind::ENCHANTMENT, [armor, move, Default::default()]).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'carrier: modifier without hit')]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 227525)] // ceil(1.05 × 216690 measured)
    fn test_carrier_modifier_without_hit_refused() {
        let [_, pierce, _] = Fixture::static_lash().entries;
        Fixture::skill(skill_kind::SPELL, [pierce, Default::default(), Default::default()])
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'carrier: modifier set')]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 242939)] // ceil(1.05 × 231370 measured)
    fn test_carrier_modifier_on_another_set_refused() {
        let [hit, pierce, _] = Fixture::static_lash().entries;
        let wide = Entry { shape: shape::RING_1, ..pierce };
        Fixture::skill(skill_kind::SPELL, [hit, wide, Default::default()]).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'carrier: attack bonus')]
    // gas: raised, CARRIER-01: assert_carrier's R-44 check
    #[available_gas(l2_gas: 186050)] // ceil(1.05 × 177190 measured)
    fn test_carrier_attack_bonus_in_a_spell_refused() {
        let [bonus, _, _] = Fixture::cleave().entries;
        let hit = Fixture::damage(damage::FIRE, 1, 2);
        Fixture::skill(skill_kind::SPELL, [hit, bonus, Default::default()]).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'carrier: attack entry')]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 74792)] // ceil(1.05 × 71230 measured)
    fn test_carrier_attack_entry_on_self_refused() {
        let heal = Entry { v0: 1, v12: 1, ..Fixture::on_self(kind::HEAL) };
        Fixture::skill(skill_kind::ATTACK, [heal, Default::default(), Default::default()])
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'carrier: trap entry')]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 161060)] // ceil(1.05 × 153390 measured)
    fn test_carrier_trap_not_first_refused() {
        let [trap, hit, cripple] = Fixture::snare().entries;
        Fixture::skill(skill_kind::TRAP, [hit, trap, cripple]).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'carrier: trap payload')]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 235452)] // ceil(1.05 × 224240 measured)
    fn test_carrier_trap_payload_on_self_refused() {
        let [trap, hit, _] = Fixture::snare().entries;
        let heal = Entry { v0: 1, v12: 1, ..Fixture::on_self(kind::HEAL) };
        Fixture::skill(skill_kind::TRAP, [trap, hit, heal]).assert_legal();
    }

    #[test]
    #[should_panic(expected: 'carrier: disc 1 not a potion')]
    // gas: raised, CARRIER-02: assert_carrier's R-45 check
    #[available_gas(l2_gas: 110681)] // ceil(1.05 × 105410 measured)
    fn test_carrier_disc_1_in_a_skill_refused() {
        let hit = Entry { shape: shape::DISC_1, ..Fixture::damage(damage::FIRE, 1, 2) };
        Fixture::skill(skill_kind::SPELL, [hit, Default::default(), Default::default()])
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'carrier: area after the MVP')]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 87360)] // ceil(1.05 × 83200 measured)
    fn test_carrier_disc_2_refused() {
        let hit = Entry { shape: shape::DISC_2, ..Fixture::damage(damage::FIRE, 1, 2) };
        Fixture::skill(skill_kind::SPELL, [hit, Default::default(), Default::default()])
            .assert_legal();
    }

    #[test]
    #[should_panic(expected: 'skill: kind')]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_skill_seal_of_capture_refused() {
        Fixture::skill(skill_kind::SEAL_OF_CAPTURE, [Default::default(); 3]).assert_legal();
    }

    // CBT-3: an attack's hit modifier takes the attacked foe: `FOES`.
    #[test]
    #[should_panic(expected: 'carrier: modifier set')]
    // gas: raised, CARRIER-01: assert_carrier's R-44 check
    #[available_gas(l2_gas: 92810)] // ceil(1.05 × 88390 measured)
    fn test_attack_bonus_on_allies_refused() {
        let bonus = Fixture::modifier_on_foe(kind::ATTACK_BONUS);
        Fixture::attack_with(Entry { filter: filter::ALLIES, ..bonus });
    }

    #[test]
    #[should_panic(expected: 'carrier: modifier set')]
    // gas: raised, CARRIER-01: assert_carrier's R-44 check
    #[available_gas(l2_gas: 93009)] // ceil(1.05 × 88580 measured)
    fn test_attack_hit_penetration_on_allies_refused() {
        let pierce = Fixture::modifier_on_foe(kind::HIT_PENETRATION);
        Fixture::attack_with(Entry { filter: filter::ALLIES, ..pierce });
    }

    #[test]
    // gas: raised, CBT-05a: the sheets carry the executor's fields, actors their positions
    #[available_gas(l2_gas: 413196)] // ceil(1.05 × 393520 measured)
    fn test_attack_modifiers_on_foes_accepted() {
        Fixture::attack_with(Fixture::modifier_on_foe(kind::ATTACK_BONUS));
        Fixture::attack_with(Fixture::modifier_on_foe(kind::HIT_PENETRATION));
    }

    #[test]
    #[available_gas(l2_gas: 2303763)] // ceil(1.05 × 2194060 measured)
    fn test_skill_profile_and_item_class() {
        for profession in array![1_u8, 6, 0xFF] {
            for elite in array![false, true] {
                let skill = SkillTrait::new(
                    profession,
                    0xFF,
                    0xFF,
                    0xFF,
                    0xFF,
                    1000,
                    1000,
                    0xFF,
                    3,
                    elite,
                    [Default::default(); 3],
                );
                let parts = skill.pack();
                let full: Skill = Record::unpack(parts);
                assert(SkillTrait::profile(*parts[0]) == (full.profession, full.elite), 'profile');
                assert(
                    SkillTrait::attribute_kind(*parts[0]) == (full.attribute, full.kind),
                    'attribute and kind',
                );
            }
        }
        let axes_attack = SkillTrait::new(
            1, 3, 1, 0, 4, 0, 0, 1, 1, false, [Default::default(); 3],
        );
        assert(SkillTrait::attribute_kind(*axes_attack.pack()[0]) == (3, 1), 'attribute 3, kind 1');
        for class in array![item_class::INGREDIENT, item_class::POTION, item_class::FAILED_BREW] {
            let item = ItemTrait::new(
                class, 0xFFFF, 0xFF, 0xFFFFFFFF, 0xFF, Default::default(), 0, 0,
            );
            assert(ItemTrait::class_of(*item.pack()[0]) == class, 'class');
        }
        assert(ItemTrait::class_of(0) == 0, 'no record');
    }
}
