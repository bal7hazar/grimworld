//! The build `Hub.set_build` receives (design/03): its word's model and packer (`Build`), its rules
//! (the attributes, the bar against the registry's `SKILL` parts, the belt against its `ITEM`
//! parts) and the loadout it gives the flattening (`models::loadout`). Pure: `Hub` runs the checks
//! that precede its `Registry.bundle` call, `FlattenLibrary` the ones that read its parts and the
//! flattening (D-168; WPN-01 moved them out of `Hub`, D-310). Its stored word, checked for its
//! layout, is `grimworld_persistent`'s `StoredBuild`.

use crate::helpers::packing::{
    LimbTrait, P112, P16, P32, P40, P48, P64, P80, P96, PackingAssert, PackingTrait,
};
use crate::models::base::{Weapon, WeaponTrait};
use crate::models::build::SnapshotBuildTrait;
use crate::models::item::{ItemTrait, class as item_class};
use crate::models::loadout::Loadout;
use crate::models::skill::SkillTrait;
use crate::models::worn::Worn;
use crate::types::combat::skill_kind;
use crate::types::content::SKILL;
use crate::types::profession::ProfessionTrait;

/// `Build.elite_slot` when no elite skill is on the bar.
pub const NO_ELITE: u8 = 255;

/// The refusals of `set_build`'s build and belt (ENG-04).
pub mod errors {
    // `set_build` (design/03, design/15; ENG-01 §4.3): one refusal per rule.
    /// The bar: the same skill twice.
    pub const DUPLICATE_SKILL: felt252 = 'build: duplicate skill';
    pub const SKILL_NOT_KNOWN: felt252 = 'build: skill not known';
    /// Not in the registry.
    pub const NO_SKILL: felt252 = 'build: no skill';
    /// Of neither its primary nor its secondary profession.
    pub const SKILL_PROFESSION: felt252 = 'build: skill profession';
    pub const TWO_ELITES: felt252 = 'build: two elites';
    /// `elite_slot` is not the elite's slot, or not `NO_ELITE` without one.
    pub const ELITE_SLOT: felt252 = 'build: elite slot';
    /// Attributes: a rank above 12, a rank in an index its professions do not have, more points
    /// than the level and the rank give.
    pub const RANK_ABOVE_12: felt252 = 'build: rank above 12';
    pub const NO_ATTRIBUTE: felt252 = 'build: no such attribute';
    pub const POINTS: felt252 = 'build: points';
    /// The belt: a count in a slot without an item, an item that is not a potion, more than the
    /// pack holds.
    pub const COUNT_WITHOUT_ITEM: felt252 = 'belt: count without item';
    pub const NOT_A_POTION: felt252 = 'belt: not a potion';
    pub const BELT_NOT_IN_PACK: felt252 = 'belt: not in the pack';
}

/// Attribute points that reaching each level gives, cumulated, levels 0 to 20 (design/03, *Base
/// stats*: 5 a level up to 10, 10 from 11 to 15, 15 from 16 to 20, 170 at level 20).
const LEVEL_POINTS: [u16; 21] = [
    0, 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 55, 65, 75, 85, 95, 110, 125, 140, 155, 170,
];
/// The last level design/03 gives points for.
const MAX_LEVEL: u8 = 20;
/// Points given at Tin and again at Copper (design/03), guild ranks 1 and 2 (design/06).
const RANK_POINTS: u16 = 15;
const TIN: u8 = 1;
const COPPER: u8 = 2;
/// What ranks 0 to 12 of one attribute cost, cumulated (design/03, *Rank cost*).
const RANK_COST: [u16; 13] = [0, 1, 3, 6, 10, 15, 21, 28, 37, 48, 61, 77, 97];
/// The highest rank points buy (design/03: ranks go from 0 to 12).
pub const MAX_RANK: u8 = 12;
/// `Build.attributes` holds nine build-local indices (D-157, A: content names a global attribute
/// id, the flattening maps it to its index): 0 to 4 the primary profession's attributes in
/// design/03's order, its primary attribute at 0; 5 to 8 the secondary's without its primary
/// attribute (design/03: the secondary gives its attributes "except its primary attribute"), in
/// the same order. An index its professions do not have holds 0.
pub const SECONDARY_FIRST: u8 = 5;
pub const ATTRIBUTE_INDICES: u8 = 9;

/// The build sent to `set_build` (design/03): the bar, the attributes, the elite slot.
#[generate_trait]
pub impl BuildImpl of BuildTrait {
    /// The bar's skills, in slot order, as `Registry.bundle` requests (`SKILL`): the checks of
    /// `BuildAssert::assert_skill` read their parts.
    fn request(self: @Build) -> Array<(u8, u32)> {
        let mut requests: Array<(u8, u32)> = array![];
        for skill in self.bar.span() {
            if *skill != 0 {
                requests.append((SKILL, (*skill).into()));
            }
        }
        requests
    }

    /// The attribute points that `level` and the guild `rank` give (design/03, *Base stats*).
    fn points(level: u8, rank: u8) -> u16 {
        let level = if level > MAX_LEVEL {
            MAX_LEVEL
        } else {
            level
        };
        let mut points = *LEVEL_POINTS.span()[level.into()];
        if rank >= TIN {
            points += RANK_POINTS;
        }
        if rank >= COPPER {
            points += RANK_POINTS;
        }
        points
    }

    /// Whether build-local index `index` names an attribute of these professions.
    fn has_attribute(index: u8, primary: u8, secondary: u8) -> bool {
        if index < SECONDARY_FIRST {
            index < ProfessionTrait::attributes(primary)
        } else {
            secondary != 0 && index - SECONDARY_FIRST + 1 < ProfessionTrait::attributes(secondary)
        }
    }

    /// The attribute of each bar skill and the slots holding an attack skill (design/19 §3.4's
    /// kind 1, slot `i` at bit `i`), from the registry's parts, two a skill in the bar's order
    /// (`BuildTrait::request`): `Loadout.bar_attributes` and `bar_attacks` (WPN-01). An empty slot
    /// has attribute 0 and no attack. Bound: 8 slots.
    fn bar_kinds(self: @Build, parts: Span<felt252>) -> ([u8; 8], u8) {
        let mut attributes: Array<u8> = array![];
        let mut attacks: u32 = 0;
        let mut bit: u32 = 1;
        let mut at: u32 = 0;
        for skill in self.bar.span() {
            if *skill == 0 {
                attributes.append(0);
            } else {
                let (attribute, kind) = SkillTrait::attribute_kind(*parts[at]);
                attributes.append(attribute);
                if kind == skill_kind::ATTACK {
                    attacks += bit;
                }
                at += 2;
            }
            bit *= 2;
        }
        let a = attributes.span();
        ([*a[0], *a[1], *a[2], *a[3], *a[4], *a[5], *a[6], *a[7]], attacks.try_into().unwrap())
    }

    /// What the snapshot's flattening reads besides the passives (`SnapshotBuildTrait::build`,
    /// D-160; `set_build` hands it to `FlattenLibrary`, D-168): the level, the primary profession,
    /// the bar, its skills' attributes and attack slots (`bar_kinds`), its elite slot, the belt,
    /// the weapon worn (`ItemBase`'s, at its requirement, D-158; all 0 with none) and whether it
    /// is personalised. What no model holds yet keeps the value the snapshot had before the
    /// flattening (`SnapshotTrait::new`; escalated in CBT-02b's report):
    /// - no attribute points: `Build.attributes` holds build-local indices, and the flattening
    ///   reads points by the global attribute ids that runes, quick-cast pairs and skills name,
    ///   which no map joins yet (D-157 A); so every attribute's rank is its runes' alone, and the
    ///   weapon's requirement counts as met only at 0 (design/15: rank ≥ requirement);
    /// - a strength cap of 0: the cap's curve is BAL-01's (DS-9);
    /// - the class's armor as the rating (design/03, D-148: the class's value until ratings are
    ///   laid out);
    /// - no set bonus: how the pieces of a set are counted is not written.
    fn loadout(
        self: @Build,
        level: u8,
        profession: u8,
        kinds: ([u8; 8], u8),
        weapon: Weapon,
        requirement: u8,
        personalised: bool,
        belt: [u32; 4],
        counts: [u8; 4],
    ) -> Loadout {
        let (bar_attributes, bar_attacks) = kinds;
        let requirement_met = if weapon.class != 0 && requirement == 0 {
            1
        } else {
            0
        };
        Loadout {
            level,
            profession,
            points: array![].span(),
            bar_attributes,
            bar_attacks,
            skills: *self.bar,
            elite_slot: *self.elite_slot,
            weapon: weapon.class,
            weapon_damage: weapon.damage,
            weapon_ticks: weapon.ticks,
            weapon_range: weapon.range,
            damage_type: weapon.damage_type,
            weapon_attribute: weapon.attribute,
            requirement_met,
            personalised,
            strength_cap: 0,
            rating: ProfessionTrait::armor(profession).into(),
            set_bonuses: 0,
            belt,
            belt_counts: counts,
        }
    }

    /// What `Hub.set_build` asks `FlattenLibrary` once its `Registry.bundle` call has answered
    /// (D-168): the bar against its parts (`BuildAssert::assert_bar`), the belt's `potions`
    /// distinct items after them (`BeltAssert::assert_potions`), then the snapshot's three words
    /// of the loadout, with the `weapon` worn (packed, `WeaponTrait::pack`) at its `requirement`
    /// and the bar's kinds read from
    /// the same parts (WPN-01), and of the items `worn`, whose distinct modifier `ids` take the
    /// parts left (`SnapshotBuildTrait::words`). `known` is one a bar skill, `primary` the
    /// profession the loadout is flattened for. Refuses what those refuse, in that order.
    fn words(
        self: @Build,
        known: Span<bool>,
        parts: Span<felt252>,
        level: u8,
        primary: u8,
        secondary: u8,
        potions: u32,
        weapon: u128,
        requirement: u8,
        personalised: bool,
        belt: [u32; 4],
        counts: [u8; 4],
        worn: Span<Worn>,
        ids: Span<u16>,
    ) -> (felt252, felt252, felt252) {
        let at = self.assert_bar(parts, known, primary, secondary);
        let modifier_parts = BeltAssert::assert_potions(parts, at, potions);
        let kinds = self.bar_kinds(parts);
        let weapon = WeaponTrait::unpack(weapon);
        let loadout = self
            .loadout(level, primary, kinds, weapon, requirement, personalised, belt, counts);
        SnapshotBuildTrait::words(@loadout, worn, ids, modifier_parts)
    }
}

#[generate_trait]
pub impl BuildAssert of BuildAssertTrait {
    /// design/03 *Attributes*: each rank at most 12, a rank only in an index its professions have,
    /// the points spent within what the level and the rank give. Bound: the nine indices.
    fn assert_attributes(self: @Build, primary: u8, secondary: u8, level: u8, rank: u8) {
        let mut rest: u64 = *self.attributes;
        let mut spent: u16 = 0;
        for index in 0..ATTRIBUTE_INDICES {
            let (next, value) = DivRem::div_rem(rest, 16);
            rest = next;
            if value == 0 {
                continue;
            }
            let value: u8 = value.try_into().unwrap();
            assert(value <= MAX_RANK, errors::RANK_ABOVE_12);
            assert(BuildTrait::has_attribute(index, primary, secondary), errors::NO_ATTRIBUTE);
            spent += *RANK_COST.span()[value.into()];
        }
        assert(spent <= BuildTrait::points(level, rank), errors::POINTS);
    }

    /// No skill twice on the bar (design/03: 8 skills equipped). Bound: 8 slots, 28 pairs.
    fn assert_distinct(self: @Build) {
        let bar = self.bar.span();
        for i in 1..8_u32 {
            let skill = *bar[i];
            if skill == 0 {
                continue;
            }
            for j in 0..i {
                assert(*bar[j] != skill, errors::DUPLICATE_SKILL);
            }
        }
    }

    /// A skill of the bar may be equipped: known by the adventurer, in the registry, of its
    /// primary or its secondary profession (design/03).
    fn assert_skill(known: bool, exists: bool, profession: u8, primary: u8, secondary: u8) {
        assert(known, errors::SKILL_NOT_KNOWN);
        assert(exists, errors::NO_SKILL);
        assert(
            profession == primary || (secondary != 0 && profession == secondary),
            errors::SKILL_PROFESSION,
        );
    }

    /// At most one elite skill (design/03): `found` is the slot of the one met so far.
    fn assert_one_elite(found: u8) {
        assert(found == NO_ELITE, errors::TWO_ELITES);
    }

    /// `elite_slot` names the elite's slot, or `NO_ELITE` when the bar has none.
    fn assert_elite_slot(self: @Build, found: u8) {
        assert(*self.elite_slot == found, errors::ELITE_SLOT);
    }

    /// The bar against the registry's parts (`Registry.bundle`, two parts a skill, in the order of
    /// `BuildTrait::request`) and what the adventurer knows (`known`, one a skill): each skill with
    /// `assert_skill`, at most one elite, and `elite_slot` naming it, in that order. Returns how
    /// many parts the bar took. Bound: 8 slots.
    fn assert_bar(
        self: @Build, parts: Span<felt252>, known: Span<bool>, primary: u8, secondary: u8,
    ) -> u32 {
        let mut at: u32 = 0;
        let mut elite = NO_ELITE;
        let mut slot: u8 = 0;
        let mut k: u32 = 0;
        for skill in self.bar.span() {
            if *skill != 0 {
                let part = *parts[at];
                let (profession, is_elite) = SkillTrait::profile(part);
                Self::assert_skill(*known[k], part != 0, profession, primary, secondary);
                if is_elite {
                    Self::assert_one_elite(elite);
                    elite = slot;
                }
                at += 2;
                k += 1;
            }
            slot += 1;
        }
        self.assert_elite_slot(elite);
        at
    }
}

#[generate_trait]
pub impl BeltAssert of BeltAssertTrait {
    /// A slot carrying a count names an item (ENG-01 §4.5: 4 slots, ≤ 255 each).
    fn assert_counts(items: [u32; 4], counts: [u8; 4]) {
        let items = items.span();
        let counts = counts.span();
        for i in 0..4_u32 {
            assert(*items[i] != 0 || *counts[i] == 0, errors::COUNT_WITHOUT_ITEM);
        }
    }

    /// A belt item is a potion of the registry (design/03: the belt's potion slots).
    fn assert_potion(exists: bool, class: u8) {
        assert(exists && class == item_class::POTION, errors::NOT_A_POTION);
    }

    /// The belt's `count` distinct items against their parts, one each from `at` on
    /// (`BeltTrait::request`'s order): each a potion. Returns the parts after them, the modifiers'
    /// (`EquipmentTrait::request`), which the flattening reads.
    fn assert_potions(parts: Span<felt252>, at: u32, count: u32) -> Span<felt252> {
        for i in at..at + count {
            let part = *parts[i];
            Self::assert_potion(part != 0, ItemTrait::class_of(part));
        }
        parts.slice(at + count, parts.len() - at - count)
    }

    /// The pack holds what the belt carries of an item (`held`), the slots of one item summed.
    fn assert_held(held: u32, count: u32) {
        assert(held >= count, errors::BELT_NOT_IN_PACK);
    }
}

/// The build (design/03): locked from entry to return.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Build {
    /// bits 0-127: the bar, 8 skill ids (0: empty)
    pub bar: [u16; 8],
    /// bits 128-163: ranks of up to nine attributes, 4 bits each, in the order of the
    /// profession's registry list (primary's attributes, then the secondary's)
    pub attributes: u64,
    /// bits 168-175: the slot of the elite skill, 255 for none
    pub elite_slot: u8,
}

pub impl BuildStorePacking of starknet::storage_access::StorePacking<Build, felt252> {
    fn pack(value: Build) -> felt252 {
        let [s0, s1, s2, s3, s4, s5, s6, s7] = value.bar;
        let low: u128 = s0.into()
            + s1.into() * P16
            + s2.into() * P32
            + s3.into() * P48
            + s4.into() * P64
            + s5.into() * P80
            + s6.into() * P96
            + s7.into() * P112;
        PackingAssert::assert_fits(
            value.attributes.into(), 0x1000000000, 'packing: attributes above 36 b',
        );
        PackingTrait::join(low, value.attributes.into() + value.elite_slot.into() * P40)
    }
    fn unpack(value: felt252) -> Build {
        let (low, high) = PackingTrait::split(value);
        Build {
            bar: [
                LimbTrait::low_field(low, P16.try_into().unwrap()).try_into().unwrap(),
                LimbTrait::u16_at(low, P16), LimbTrait::u16_at(low, P32),
                LimbTrait::u16_at(low, P48), LimbTrait::u16_at(low, P64),
                LimbTrait::u16_at(low, P80), LimbTrait::u16_at(low, P96),
                LimbTrait::u16_at(low, P112),
            ],
            attributes: LimbTrait::field(high, 1, 0x1000000000).try_into().unwrap(),
            elite_slot: LimbTrait::byte_at(high, P40),
        }
    }
}
