//! An adventurer (design/03): six consecutive slots under its id. Layouts:
//! docs/architecture/ENG-01-interfaces.md, *Hub storage*. The models of its words and their
//! packers (the layout, and the oracle of the stored models), the build's and the belt's rules, the
//! adventurer's checks. Its hot words as stored, read and changed by arithmetic, are in
//! `stored_core`, `stored_place` and `stored_build` (ENG-R1a).

use grimworld_logic::content::{ITEM, SKILL};
use grimworld_logic::models::gate::errors as gate_errors;
use grimworld_logic::models::item::{ItemTrait, class as item_class};
use grimworld_logic::models::skill::SkillTrait;
use grimworld_logic::packing::{
    Bitmap, LIVE, Lanes32, P104, P112, P12, P120, P16, P24, P32, P36, P4, P40, P48, P56, P64, P8,
    P80, P96, byte_at, field, fits, join, low_field, split, u16_at, u32_at,
};
use grimworld_logic::professions::ProfessionTrait;
use grimworld_logic::snapshot::Loadout;
use starknet::ContractAddress;
use crate::helpers::BitTrait;
use super::item::{Equipment, Gold, ItemBaseAssert, ItemBaseTrait};
use super::lanes::{StoredLanes, StoredLanesTrait};
use super::stored_build::{NEW_BUILD, StoredBuild};
use super::stored_core::{StoredCore, StoredCoreTrait};
use super::stored_place::{StoredPlace, StoredPlaceTrait};

/// `AdventurerCore.status`: an adventurer is never zeroed; deletion marks it (design/03, D-33).
pub const ACTIVE: u8 = 0;
pub const DELETED: u8 = 1;
/// `Build.elite_slot` when no elite skill is on the bar.
pub const NO_ELITE: u8 = 255;
/// Words of `Adventurer`, six consecutive slots (the view `IHubViews::adventurer` returns them).
pub const WORDS: u8 = 6;

/// The refusals of adventurers (ENG-04).
pub mod errors {
    pub const EMPTY_NAME: felt252 = 'empty name';
    // The ownership check of every entrypoint that names an adventurer, one refusal per case.
    pub const NO_ADVENTURER: felt252 = 'no adventurer';
    pub const NOT_OWNER: felt252 = 'not owner';
    pub const ADVENTURER_DELETED: felt252 = 'adventurer deleted';
    pub const NOT_IN_HUB: felt252 = 'not in a hub';
    // `delete_adventurer`: what "its inventory emptied" covers (design/03, D-33).
    pub const PACK_HOLDS_ITEMS: felt252 = 'pack holds items';
    pub const PACK_HOLDS_EQUIPMENT: felt252 = 'pack holds equipment';
    pub const WEARS_EQUIPMENT: felt252 = 'wears equipment';
    pub const PACK_HOLDS_GOLD: felt252 = 'pack holds gold';
    // Places (ENG-06).
    /// `AdventurerPlace.unlocked` holds hub ids below 64.
    pub const HUB_ABOVE_63: felt252 = 'hub above 63';
    /// Map travel to a hub not unlocked (design/01 *Connectivity*).
    pub const NOT_UNLOCKED: felt252 = 'hub not unlocked';
    /// Region 1 is not in the registry: no start hub (D-144).
    pub const NO_START_REGION: felt252 = 'no start region';
    /// A report for an adventurer not inside that instance.
    pub const NOT_ITS_INSTANCE: felt252 = 'not its instance';
    /// Experience past a `u32`.
    pub const EXPERIENCE_OVERFLOW: felt252 = 'experience overflow';
    // `set_build` (design/03, design/15; ENG-01 §4.3): one refusal per rule.
    /// A bit outside the fields of `Build`, `belt` or `equipped` (they come without `LIVE`).
    pub const BUILD_LAYOUT: felt252 = 'build: layout';
    pub const BELT_LAYOUT: felt252 = 'belt: layout';
    pub const EQUIPPED_LAYOUT: felt252 = 'equipped: layout';
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
    /// The equipment: the same entity in two slots, an item of another slot (or of none), a
    /// weapon in both hands with an off-hand.
    pub const DUPLICATE_ITEM: felt252 = 'equipped: duplicate';
    pub const WRONG_SLOT: felt252 = 'equipped: wrong slot';
    pub const TWO_HANDS: felt252 = 'equipped: two hands';
}

#[generate_trait]
pub impl AdventurerImpl of AdventurerTrait {
    /// The six words of a new adventurer (D-32): its core, placed in `hub` (region 1's town,
    /// D-144), the empty build, no belt, nothing worn; its name is the sixth.
    #[inline(always)]
    fn new(account: u32, profession: u8, hub: u16) -> (StoredCore, StoredPlace, StoredBuild) {
        (
            StoredCoreTrait::new(account, profession),
            StoredPlaceTrait::new(hub),
            StoredBuild {
                build: NEW_BUILD, belt: StoredLanesTrait::new(), equipped: StoredLanesTrait::new(),
            },
        )
    }
}

/// The belt word (`Lanes32`): the potion item of each slot in lanes 0-3, the count to carry in
/// each slot in lane 4, 8 bits a slot (ENG-01 §3.3). Read as its stored word: its seven lanes are
/// not all needed.
#[generate_trait]
pub impl BeltImpl of BeltTrait {
    /// `(items, counts)` of a stored belt, its two limbs decoded in one pass.
    fn read(belt: @StoredLanes) -> ([u32; 4], [u8; 4]) {
        let (low, high) = split(*belt.word);
        let s32: NonZero<u128> = P32.try_into().unwrap();
        let (low, a) = DivRem::div_rem(low, s32);
        let (low, b) = DivRem::div_rem(low, s32);
        let (d, c) = DivRem::div_rem(low, s32);
        (
            [
                a.try_into().unwrap(), b.try_into().unwrap(), c.try_into().unwrap(),
                d.try_into().unwrap(),
            ],
            [
                low_field(high, P8.try_into().unwrap()).try_into().unwrap(), byte_at(high, P8),
                byte_at(high, P16), byte_at(high, P24),
            ],
        )
    }

    /// The belt's distinct items, in slot order, as `Registry.bundle` requests (`ITEM`) appended
    /// to `requests`: the check that each is a potion (`BeltAssert::assert_potions`). Returns how
    /// many it appended.
    fn request(items: [u32; 4], ref requests: Array<(u8, u32)>) -> u32 {
        let slots = items.span();
        let mut count = 0;
        for i in 0..4_u32 {
            let item = *slots[i];
            if item == 0 {
                continue;
            }
            let mut first = true;
            for j in 0..i {
                if *slots[j] == item {
                    first = false;
                }
            }
            if first {
                requests.append((ITEM, item));
                count += 1;
            }
        }
        count
    }
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
/// `known_skills`: a `Bitmap` of 250 skill ids a page (ENG-01 §3.3).
pub const SKILLS_PER_PAGE: u16 = 250;

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

    /// What the snapshot's flattening reads besides the passives (`SnapshotBuildTrait::build`,
    /// D-160; `set_build` hands it to `FlattenLibrary`, D-168): the level, the primary profession,
    /// the bar and its elite slot, the belt, whether the weapon is personalised. What no model
    /// holds yet keeps the value the snapshot had before the flattening (`SnapshotTrait::new`;
    /// escalated in CBT-02b's report):
    /// - no attribute rank: `Build.attributes` holds build-local indices, and the global attribute
    ///   ids that runes, quick-cast pairs and skills name are not numbered (D-157 A);
    /// - no weapon statistics and a strength cap of 0: `BASE` lays out only the slot and the hands
    ///   (D-158), and the cap's curve is BAL-01's (DS-9);
    /// - the class's armor as the rating (design/03, D-148: the class's value until ratings are
    ///   laid out);
    /// - no set bonus: how the pieces of a set are counted is not written.
    fn loadout(
        self: @Build,
        level: u8,
        profession: u8,
        personalised: bool,
        belt: [u32; 4],
        counts: [u8; 4],
    ) -> Loadout {
        Loadout {
            level,
            profession,
            points: array![].span(),
            bar_attributes: [0; 8],
            skills: *self.bar,
            elite_slot: *self.elite_slot,
            weapon: 0,
            weapon_damage: 0,
            weapon_ticks: 0,
            weapon_range: 0,
            damage_type: 0,
            weapon_attribute: 0,
            requirement_met: 0,
            personalised,
            strength_cap: 0,
            rating: ProfessionTrait::armor(profession).into(),
            set_bonuses: 0,
            belt,
            belt_counts: counts,
        }
    }
}

#[generate_trait]
pub impl BuildAssert of BuildAssertTrait {
    /// The stored word of a `Build` sent without `LIVE` (ENG-01 §4.3); a bit outside its fields
    /// (164-167, 176 and up) is refused.
    fn assert_layout(build: felt252) -> felt252 {
        let (_, high) = BitTrait::limbs(build);
        let (above, _) = DivRem::div_rem(high, P36.try_into().unwrap());
        assert(above < P12 && above % P4 == 0, errors::BUILD_LAYOUT);
        build + LIVE
    }

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

/// `known_skills` pages (ENG-01 §3.3): bit `skill % 250` of page `skill / 250`.
#[generate_trait]
pub impl KnownSkillsImpl of KnownSkillsTrait {
    /// `(page, bit)` of a skill id; a page past a `u8` holds no skill (none is known there).
    fn at(skill: u16) -> (u8, u8) {
        let (page, bit) = DivRem::div_rem(skill, SKILLS_PER_PAGE.try_into().unwrap());
        (page.try_into().expect(errors::SKILL_NOT_KNOWN), bit.try_into().unwrap())
    }

    /// Whether bit `bit` (0 to 249) of a page is set; a page never written knows none.
    fn knows(page: @Bitmap, bit: u8) -> bool {
        let (low, high) = split(*page.bits);
        if bit < 128 {
            BitTrait::is_set(low, bit)
        } else {
            BitTrait::is_set(high, bit - 128)
        }
    }
}

#[generate_trait]
pub impl BeltAssert of BeltAssertTrait {
    /// The stored word of a belt sent without `LIVE`: lanes 5 and 6 are empty (ENG-01 §3.3).
    fn assert_layout(belt: felt252) -> felt252 {
        let (_, high) = BitTrait::limbs(belt);
        assert(high < P32, errors::BELT_LAYOUT);
        belt + LIVE
    }

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

/// `equipped`: seven entities, lanes weapon, off-hand, chest, legs, head, hands, feet (ENG-01
/// §3.3).
#[generate_trait]
pub impl EquippedAssert of EquippedAssertTrait {
    /// The stored word of `equipped` sent without `LIVE`: nothing above lane 6.
    fn assert_layout(equipped: felt252) -> felt252 {
        let (_, high) = BitTrait::limbs(equipped);
        assert(high < P96, errors::EQUIPPED_LAYOUT);
        equipped + LIVE
    }

    /// No entity in two slots. Bound: 7 lanes, 21 pairs.
    fn assert_distinct(entities: Span<u32>) {
        for i in 1..7_u32 {
            let entity = *entities[i];
            if entity == 0 {
                continue;
            }
            for j in 0..i {
                assert(*entities[j] != entity, errors::DUPLICATE_ITEM);
            }
        }
    }

    /// The item is worn in lane `lane`'s slot (design/15): `slot` is `ItemBase.slot`, its base's
    /// slot copied at creation (D-158); 0, an item not worn, fits no lane.
    fn assert_slot(slot: u8, lane: u32) {
        let slot: u32 = slot.into();
        assert(slot == lane + 1, errors::WRONG_SLOT);
    }

    /// A weapon held in both hands leaves the off-hand empty (design/15, *Weapons*: hands 2).
    fn assert_hands(two_handed: bool, off_hand: u32) {
        assert(!two_handed || off_hand == 0, errors::TWO_HANDS);
    }

    /// The items worn (`HubStore::get_equipment`), in lane order: each wearable by the adventurer
    /// and in its lane's slot; then no off-hand (`entities`' lane 1) beside a weapon held in both
    /// hands.
    fn assert_worn(equipment: @Equipment, adventurer_id: u32, entities: Span<u32>) {
        let mut two_handed = false;
        for (lane, item) in equipment.bases.span() {
            item.assert_wearable(adventurer_id);
            Self::assert_slot(*item.slot, *lane);
            if *lane == 0 {
                two_handed = item.is_two_handed();
            }
        }
        Self::assert_hands(two_handed, *entities[1]);
    }
}

#[generate_trait]
pub impl AdventurerAssert of AdventurerAssertTrait {
    /// A name is not empty (D-32).
    fn assert_valid_name(name: felt252) {
        assert(name != 0, errors::EMPTY_NAME);
    }

    /// The ownership check of every entrypoint that names an adventurer (ADR-0007, *Access
    /// control*; ENG-01 §1.2), from its core's account and status, its place and its account's
    /// owner: it exists, the caller owns its account, it is not deleted, and it is in a hub (not
    /// inside).
    fn assert_owned_in_hub(
        account_id: u32,
        status: u8,
        place: @StoredPlace,
        owner: ContractAddress,
        caller: ContractAddress,
    ) {
        assert(account_id != 0, errors::NO_ADVENTURER);
        assert(owner == caller, errors::NOT_OWNER);
        assert(status != DELETED, errors::ADVENTURER_DELETED);
        assert(!place.is_inside(), errors::NOT_IN_HUB);
    }

    /// "Its inventory emptied" (design/03, D-33), each from one slot: the pack's balance lanes
    /// (`core.pack_lanes`), page 0 of its equipment list (compact: empty when page 0 is), what it
    /// wears, its gold. A slot never written reads empty.
    fn assert_emptied(
        pack_lanes: u16, pack_page: @StoredLanes, equipped: @StoredLanes, gold: @Gold,
    ) {
        assert(pack_lanes == 0, errors::PACK_HOLDS_ITEMS);
        assert(pack_page.is_empty(), errors::PACK_HOLDS_EQUIPMENT);
        assert(equipped.is_empty(), errors::WEARS_EQUIPMENT);
        assert(*gold.amount == 0, errors::PACK_HOLDS_GOLD);
    }

    /// Map travel goes to an unlocked hub (design/01 *Connectivity*).
    fn assert_unlocked(place: @StoredPlace, hub: u16) {
        assert(place.is_unlocked(hub), errors::NOT_UNLOCKED);
    }

    /// `enter`: the gate is in the registry (`Registry.bundle` returns its parts zero otherwise).
    fn assert_gate(exists: bool) {
        assert(exists, gate_errors::NONE);
    }

    /// Experience stays within a `u32` (`StoredCoreTrait::with_experience`).
    fn assert_experience(experience: u32, amount: u32) {
        let total: u64 = experience.into() + amount.into();
        assert(total <= 0xFFFFFFFF, errors::EXPERIENCE_OVERFLOW);
    }

    /// The refusal of a hub id of 64 or more (`AdventurerPlace.unlocked` holds bits 0-63): the
    /// last arm of `StoredPlaceTrait::bit`, which never returns.
    fn hub_above_63() -> core::never {
        core::panic_with_felt252(errors::HUB_ABOVE_63)
    }

    /// D-144: the start hub is region 1's town, read from the registry.
    fn assert_start_region(exists: bool) {
        assert(exists, errors::NO_START_REGION);
    }

    /// A report is about the instance its first contributor is inside (ENG-01 §6).
    fn assert_in_instance(place: @StoredPlace, instance: u64) {
        let (current, _, _, inside) = place.fields();
        assert(inside && current == instance, errors::NOT_ITS_INSTANCE);
    }
}

/// Who it is and how far it went.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct AdventurerCore {
    /// bits 0-31
    pub account: u32,
    /// bits 32-63
    pub experience: u32,
    /// bits 64-95
    pub merit: u32,
    /// bits 96-103, 104-111
    pub level: u8,
    pub rank: u8,
    /// bits 112-119, 120-127: primary and secondary profession (0: none)
    pub profession: u8,
    pub secondary: u8,
    /// bits 128-143: attribute points not spent
    pub unspent: u16,
    /// bits 144-159: bit `r`, the trial of rank `r` passed at the first attempt (Flawless)
    pub trials_first: u16,
    /// bits 160-175: bit `r`, a trial of rank `r` attempted
    pub trials_tried: u16,
    /// bits 176-183: 0 active, 1 deleted (its slot freed, design/03)
    pub status: u8,
    /// bits 184-199: non-zero balance lanes in its pack, so that `delete_adventurer` checks an
    /// empty pack without scanning pages (design/03, D-33; ENG-01 fix loop 1, F-5)
    pub pack_lanes: u16,
}

pub impl AdventurerCoreStorePacking of starknet::storage_access::StorePacking<
    AdventurerCore, felt252,
> {
    fn pack(value: AdventurerCore) -> felt252 {
        let low: u128 = value.account.into()
            + value.experience.into() * P32
            + value.merit.into() * P64
            + value.level.into() * P96
            + value.rank.into() * P104
            + value.profession.into() * P112
            + value.secondary.into() * P120;
        let high: u128 = value.unspent.into()
            + value.trials_first.into() * P16
            + value.trials_tried.into() * P32
            + value.status.into() * P48
            + value.pack_lanes.into() * P56;
        join(low, high)
    }
    fn unpack(value: felt252) -> AdventurerCore {
        let (low, high) = split(value);
        AdventurerCore {
            account: low_field(low, P32.try_into().unwrap()).try_into().unwrap(),
            experience: u32_at(low, P32),
            merit: u32_at(low, P64),
            level: byte_at(low, P96),
            rank: byte_at(low, P104),
            profession: byte_at(low, P112),
            secondary: byte_at(low, P120),
            unspent: low_field(high, P16.try_into().unwrap()).try_into().unwrap(),
            trials_first: u16_at(high, P16),
            trials_tried: u16_at(high, P32),
            status: byte_at(high, P48),
            pack_lanes: u16_at(high, P56),
        }
    }
}

/// Where it is (D-03: the chain only knows who is in which hub).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct AdventurerPlace {
    /// bits 0-63: its instance while inside (design/02: adventurers reference their instance)
    pub instance: u64,
    /// bits 64-79: its hub, 0 while in an instance
    pub hub: u16,
    /// bits 80-95: the last hub visited (where a defeat sends it, D-04)
    pub last_hub: u16,
    /// bits 96-103: 1 inside an instance
    pub inside: u8,
    /// bits 128-191: hubs unlocked, bit per hub id below 64 (map travel, design/01)
    pub unlocked: u64,
}

pub impl AdventurerPlaceStorePacking of starknet::storage_access::StorePacking<
    AdventurerPlace, felt252,
> {
    fn pack(value: AdventurerPlace) -> felt252 {
        join(
            value.instance.into()
                + value.hub.into() * P64
                + value.last_hub.into() * P80
                + value.inside.into() * P96,
            value.unlocked.into(),
        )
    }
    fn unpack(value: felt252) -> AdventurerPlace {
        let (low, high) = split(value);
        AdventurerPlace {
            instance: low_field(low, P64.try_into().unwrap()).try_into().unwrap(),
            hub: u16_at(low, P64),
            last_hub: u16_at(low, P80),
            inside: byte_at(low, P96),
            unlocked: low_field(high, P64.try_into().unwrap()).try_into().unwrap(),
        }
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
        fits(value.attributes.into(), 0x1000000000, 'packing: attributes above 36 b');
        join(low, value.attributes.into() + value.elite_slot.into() * P40)
    }
    fn unpack(value: felt252) -> Build {
        let (low, high) = split(value);
        Build {
            bar: [
                low_field(low, P16.try_into().unwrap()).try_into().unwrap(), u16_at(low, P16),
                u16_at(low, P32), u16_at(low, P48), u16_at(low, P64), u16_at(low, P80),
                u16_at(low, P96), u16_at(low, P112),
            ],
            attributes: field(high, 1, 0x1000000000).try_into().unwrap(),
            elite_slot: byte_at(high, P40),
        }
    }
}

/// Six consecutive slots under an adventurer id.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Adventurer {
    pub core: AdventurerCore,
    pub place: AdventurerPlace,
    pub build: Build,
    /// Lanes 0-3: the potion item of each belt slot (the potions themselves are in the pack).
    pub belt: Lanes32,
    /// Lanes: weapon, off-hand, chest, legs, head, hands, feet (item entities, 0: none).
    pub equipped: Lanes32,
    /// A short string (design/03, D-32).
    pub name: felt252,
}

#[cfg(test)]
mod tests {
    use grimworld_logic::packing::{Bitmap, LIVE, Lanes32};
    use starknet::storage_access::StorePacking;
    use super::super::account::PACK;
    use super::super::item::{COMMON, EquipmentTrait, Item, ItemBase, ItemMods, Modifier};
    use super::super::lanes::StoredLanes;
    use super::super::stored_build::NEW_BUILD;
    use super::super::stored_core::StoredCore;
    use super::super::stored_place::{StoredPlace, StoredPlaceTrait};
    use super::{
        ACTIVE, AdventurerCore, AdventurerPlace, AdventurerTrait, BeltAssert, BeltTrait, Build,
        BuildAssert, BuildTrait, EquippedAssert, KnownSkillsTrait, NO_ELITE,
    };

    const TWO_128: felt252 = 0x100000000000000000000000000000000;
    const ARCANIST: u8 = 3;

    fn stored_place(model: AdventurerPlace) -> StoredPlace {
        StoredPlace { word: StorePacking::pack(model) }
    }

    fn stored_core(model: AdventurerCore) -> StoredCore {
        StoredCore { word: StorePacking::pack(model) }
    }

    // The words of a new adventurer against the packers (ENG-04's `test_stored_words`).
    #[test]
    #[available_gas(l2_gas: 146160)] // ceil(1.05 × 139200 measured)
    fn test_new_adventurer_words() {
        let (new_core, new_place, build) = AdventurerTrait::new(0xFFFFFFFF, ARCANIST, 5);
        let expected = AdventurerCore {
            account: 0xFFFFFFFF,
            level: 1,
            profession: ARCANIST,
            status: ACTIVE,
            ..Default::default(),
        };
        assert(new_core == stored_core(expected), 'new core');
        let at_start = AdventurerPlace {
            instance: 0, hub: 5, last_hub: 5, inside: 0, unlocked: 0x20,
        };
        assert(new_place == stored_place(at_start), 'new place');
        assert(!new_place.is_inside(), 'new: in a hub');
        let empty = Build { bar: [0; 8], attributes: 0, elite_slot: NO_ELITE };
        assert(build.build == NEW_BUILD && NEW_BUILD == StorePacking::pack(empty), 'new build');
        let no_lanes: felt252 = StorePacking::pack(Lanes32 { lanes: [0; 7] });
        assert(build.belt.word == no_lanes && build.equipped.word == no_lanes, 'no belt, nothing');
    }

    #[test]
    #[available_gas(l2_gas: 293171)] // ceil(1.05 × 279210 measured)
    fn test_adventurer_layout() {
        let full = AdventurerCore {
            account: 0xFFFFFFFF,
            experience: 140600,
            merit: 50000,
            level: 20,
            rank: 9,
            profession: 3,
            secondary: 6,
            unspent: 200,
            trials_first: 0x3FF,
            trials_tried: 0x3FF,
            status: 1,
            pack_lanes: 0xFFFF,
        };
        let word = stored_core(full).word;
        assert(StorePacking::<AdventurerCore, felt252>::unpack(word) == full, 'core trip');
        assert(starknet::Store::<super::Adventurer>::size() == 6, 'adventurer: 6 slots');
        let rank = AdventurerCore { rank: 1, ..Default::default() };
        assert(stored_core(rank).word == 0x100000000000000000000000000 + LIVE, 'rank at bit 104');

        let anywhere = AdventurerPlace {
            instance: 0xFFFFFFFFFFFFFFFF,
            hub: 1,
            last_hub: 0xFFFF,
            inside: 1,
            unlocked: 0xFFFFFFFFFFFFFFFF,
        };
        let word = stored_place(anywhere).word;
        assert(StorePacking::<AdventurerPlace, felt252>::unpack(word) == anywhere, 'place trip');

        let build = Build {
            bar: [1, 2, 3, 4, 5, 6, 7, 0xFFFF], attributes: 0xFFFFFFFFF, elite_slot: 255,
        };
        let word = StorePacking::<Build, felt252>::pack(build);
        assert(StorePacking::<Build, felt252>::unpack(word) == build, 'build trip');
        let attributes = Build { bar: [0; 8], attributes: 1, elite_slot: 0 };
        assert(
            StorePacking::<Build, felt252>::pack(attributes) == TWO_128 + LIVE, 'attributes at 128',
        );
    }

    // Fix loop 1, F-9: fields narrower than their type are refused when too wide.
    #[test]
    #[should_panic(expected: 'packing: attributes above 36 b')]
    #[available_gas(l2_gas: 43418)] // ceil(1.05 × 41350 measured)
    fn test_attributes_above_36_bits_refused() {
        StorePacking::<
            Build, felt252,
        >::pack(Build { bar: [0; 8], attributes: 0x1000000000, elite_slot: 0 });
    }

    #[test]
    #[available_gas(l2_gas: 137309)] // ceil(1.05 × 130770 measured)
    fn test_belt_word() {
        let counts: u32 = 0xFF + 0x2 * 0x100 + 0x3 * 0x10000 + 0x80 * 0x1000000;
        let belt = Lanes32 { lanes: [0xFFFFFFFF, 2, 3, 0x12345678, counts, 0, 0] };
        let (items, amounts) = BeltTrait::read(@StoredLanes { word: StorePacking::pack(belt) });
        assert(items == [0xFFFFFFFF, 2, 3, 0x12345678], 'items');
        assert(amounts == [0xFF, 2, 3, 0x80], 'counts');
        assert(BeltTrait::read(@StoredLanes { word: 0 }) == ([0; 4], [0; 4]), 'never written');
        let mut requests = array![];
        BeltTrait::request([4, 9, 4, 0], ref requests);
        assert(requests == array![(11, 4), (11, 9)], 'distinct items');
    }

    // The bar against its parts (two a skill), the elite, the potions (one part an item).
    #[test]
    #[available_gas(l2_gas: 42231)] // ceil(1.05 × 40220 measured)
    fn test_assert_bar_and_potions() {
        let empty = Build { bar: [0; 8], attributes: 0, elite_slot: NO_ELITE };
        assert(empty.assert_bar(array![].span(), array![].span(), 1, 0) == 0, 'empty bar');
        assert(BeltAssert::assert_potions(array![5].span(), 0, 0) == array![5].span(), 'no potion');
    }

    #[test]
    #[should_panic(expected: 'build: skill not known')]
    #[available_gas(l2_gas: 27731)] // ceil(1.05 × 26410 measured)
    fn test_assert_bar_unknown_refused() {
        let bar = Build { bar: [4, 0, 0, 0, 0, 0, 0, 0], attributes: 0, elite_slot: NO_ELITE };
        bar.assert_bar(array![0, 0].span(), array![false].span(), 1, 0);
    }

    #[test]
    #[should_panic(expected: 'belt: not a potion')]
    #[available_gas(l2_gas: 27794)] // ceil(1.05 × 26470 measured)
    fn test_assert_potions_refused() {
        BeltAssert::assert_potions(array![0, 0, 0].span(), 2, 1);
    }

    /// A skill's part 0 (`SkillTrait::profile`): its profession in the low byte, bit 82 elite.
    fn skill_part(profession: u8, elite: bool) -> felt252 {
        let elite: felt252 = if elite {
            0x400000000000000000000
        } else {
            0
        };
        profession.into() + elite
    }

    // The elite walk: two parts a skill, the elite's slot found and matched, empty slots skipped.
    #[test]
    #[available_gas(l2_gas: 151494)] // ceil(1.05 × 144280 measured)
    fn test_assert_bar_elite() {
        let bar = Build { bar: [4, 0, 5, 0, 0, 0, 0, 6], attributes: 0, elite_slot: 2 };
        let parts = array![
            skill_part(1, false), 0, skill_part(2, true), 0, skill_part(1, false), 0, 99,
        ];
        let known = array![true, true, true];
        assert(bar.assert_bar(parts.span(), known.span(), 1, 2) == 6, 'six parts');
        let none = Build { elite_slot: NO_ELITE, ..bar };
        let plain = array![
            skill_part(1, false), 0, skill_part(2, false), 0, skill_part(1, false), 0,
        ];
        assert(none.assert_bar(plain.span(), known.span(), 1, 2) == 6, 'no elite');
    }

    #[test]
    #[should_panic(expected: 'build: two elites')]
    #[available_gas(l2_gas: 46389)] // ceil(1.05 × 44180 measured)
    fn test_assert_bar_two_elites_refused() {
        let bar = Build { bar: [4, 5, 0, 0, 0, 0, 0, 0], attributes: 0, elite_slot: 0 };
        let parts = array![skill_part(1, true), 0, skill_part(1, true), 0];
        bar.assert_bar(parts.span(), array![true, true].span(), 1, 0);
    }

    #[test]
    #[should_panic(expected: 'build: elite slot')]
    #[available_gas(l2_gas: 67683)] // ceil(1.05 × 64460 measured)
    fn test_assert_bar_elite_slot_refused() {
        let bar = Build { bar: [4, 5, 0, 0, 0, 0, 0, 0], attributes: 0, elite_slot: 0 };
        let parts = array![skill_part(1, false), 0, skill_part(1, true), 0];
        bar.assert_bar(parts.span(), array![true, true].span(), 1, 0);
    }

    #[test]
    #[should_panic(expected: 'build: skill profession')]
    #[available_gas(l2_gas: 30954)] // ceil(1.05 × 29480 measured)
    fn test_assert_bar_profession_refused() {
        let bar = Build { bar: [4, 0, 0, 0, 0, 0, 0, 0], attributes: 0, elite_slot: NO_ELITE };
        bar.assert_bar(array![skill_part(3, false), 0].span(), array![true].span(), 1, 2);
    }

    fn worn(slot: u8, hands: u8) -> Item {
        let base = ItemBase {
            owner_kind: PACK, owner: 5, slot, hands, rarity: COMMON, ..Default::default(),
        };
        Item { base, mods: ItemMods { mods: [Modifier { id: 0, value: 0 }; 5] } }
    }

    // The items worn: each wearable and in its lane's slot, no off-hand beside two hands.
    #[test]
    #[available_gas(l2_gas: 143995)] // ceil(1.05 × 137138 measured)
    fn test_assert_worn() {
        let mut equipment = EquipmentTrait::new();
        equipment.add(0, worn(1, 2));
        equipment.add(2, worn(3, 0));
        EquippedAssert::assert_worn(@equipment, 5, array![10, 0, 12, 0, 0, 0, 0].span());
        let mut one_hand = EquipmentTrait::new();
        one_hand.add(0, worn(1, 1));
        one_hand.add(1, worn(2, 0));
        EquippedAssert::assert_worn(@one_hand, 5, array![10, 11, 0, 0, 0, 0, 0].span());
        EquippedAssert::assert_worn(@EquipmentTrait::new(), 5, array![0, 0, 0, 0, 0, 0, 0].span());
    }

    #[test]
    #[should_panic(expected: 'equipped: two hands')]
    #[available_gas(l2_gas: 81185)] // ceil(1.05 × 77319 measured)
    fn test_assert_worn_two_hands_refused() {
        let mut equipment = EquipmentTrait::new();
        equipment.add(0, worn(1, 2));
        equipment.add(1, worn(2, 0));
        EquippedAssert::assert_worn(@equipment, 5, array![10, 11, 0, 0, 0, 0, 0].span());
    }

    #[test]
    #[should_panic(expected: 'equipped: wrong slot')]
    #[available_gas(l2_gas: 48839)] // ceil(1.05 × 46513 measured)
    fn test_assert_worn_wrong_slot_refused() {
        let mut equipment = EquipmentTrait::new();
        equipment.add(2, worn(4, 0));
        EquippedAssert::assert_worn(@equipment, 5, array![0, 0, 12, 0, 0, 0, 0].span());
    }

    #[test]
    #[should_panic(expected: 'item: not in the pack')]
    #[available_gas(l2_gas: 43218)] // ceil(1.05 × 41160 measured)
    fn test_assert_worn_not_in_pack_refused() {
        let mut equipment = EquipmentTrait::new();
        equipment.add(2, worn(3, 0));
        EquippedAssert::assert_worn(@equipment, 6, array![0, 0, 12, 0, 0, 0, 0].span());
    }

    // CBT-08a: bit `skill % 250` of page `skill / 250`, in both limbs.
    #[test]
    #[available_gas(l2_gas: 174185)] // ceil(1.05 × 165890 measured)
    fn test_known_skills_bits() {
        assert(KnownSkillsTrait::at(0) == (0, 0), '0');
        assert(KnownSkillsTrait::at(249) == (0, 249), '249');
        assert(KnownSkillsTrait::at(250) == (1, 0), '250');
        assert(KnownSkillsTrait::at(63999) == (255, 249), 'last page');
        // Bits 0, 127, 128, 249.
        let bits: felt252 = 1
            + 0x80000000000000000000000000000000
            + 0x100000000000000000000000000000000
            + 0x200000000000000000000000000000000000000000000000000000000000000;
        let stored: Bitmap = StorePacking::unpack(StorePacking::pack(Bitmap { bits }));
        for bit in array![0_u8, 127, 128, 249] {
            assert(KnownSkillsTrait::knows(@stored, bit), 'known');
        }
        for bit in array![1_u8, 126, 129, 248] {
            assert(!KnownSkillsTrait::knows(@stored, bit), 'unknown');
        }
        let never: Bitmap = StorePacking::unpack(0);
        assert(!KnownSkillsTrait::knows(@never, 0), 'never written');
    }

    #[test]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    #[should_panic(expected: 'build: skill not known')]
    fn test_known_skills_past_page_255() {
        KnownSkillsTrait::at(64000);
    }

    // design/03's points against its rule as a loop: 5 a level up to 10, 10 from 11 to 15, 15
    // from 16 to 20, 15 at Tin and 15 at Copper.
    #[test]
    #[available_gas(l2_gas: 313205)] // ceil(1.05 × 298290 measured)
    fn test_attribute_points() {
        let mut expected: u16 = 0;
        for level in 1..21_u8 {
            if level >= 2 {
                expected += if level <= 10 {
                    5
                } else if level <= 15 {
                    10
                } else {
                    15
                };
            }
            assert(BuildTrait::points(level, 0) == expected, 'wood');
            assert(BuildTrait::points(level, 1) == expected + 15, 'tin');
            assert(BuildTrait::points(level, 9) == expected + 30, 'copper and above');
        }
        assert(BuildTrait::points(20, 2) == 200, '200 at level 20');
        assert(BuildTrait::points(255, 2) == 200, 'no level above 20');
    }

    // D-157 A: 0-4 the primary's attributes, 5-8 the secondary's without its primary attribute.
    #[test]
    #[available_gas(l2_gas: 101903)] // ceil(1.05 × 97050 measured)
    fn test_attribute_indices() {
        for index in 0..9_u8 {
            // A Vanguard (5) with a Warden secondary (4, so 3 at 5-7).
            assert(BuildTrait::has_attribute(index, 1, 2) == (index != 8), 'vanguard, warden');
            // A Warden (4) alone.
            assert(BuildTrait::has_attribute(index, 2, 0) == (index < 4), 'warden alone');
            // An Arcanist (5) with a Vanguard secondary (5, so 4 at 5-8).
            assert(BuildTrait::has_attribute(index, 3, 1), 'arcanist, vanguard');
        }
    }
}
