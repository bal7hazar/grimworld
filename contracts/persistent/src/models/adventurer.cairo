//! An adventurer (design/03): six consecutive slots under its id. Layouts:
//! docs/architecture/ENG-01-interfaces.md, *Hub storage*. The models of its words and their
//! packers (the layout, and the oracle of the stored models), the belt's word, the equipment's and
//! the adventurer's checks. Its hot words as stored, read and changed by arithmetic, are in
//! `stored_core`, `stored_place` and `stored_build` (ENG-R1a). The build word's model and its
//! rules are `grimworld_logic::models::sent_build`'s (WPN-01), re-exported here.

use grimworld_logic::helpers::packing::{
    Bitmap, Lanes32, LimbTrait, P104, P112, P120, P16, P24, P32, P48, P56, P64, P8, P80, P96,
    PackingAssert, PackingTrait,
};
pub use grimworld_logic::models::sent_build::{
    ATTRIBUTE_INDICES, BeltAssert, BeltAssertTrait, Build, BuildAssert, BuildAssertTrait,
    BuildStorePacking, BuildTrait, MAX_RANK, NO_ELITE, SECONDARY_FIRST,
};
use grimworld_logic::types::content::ITEM;
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
    /// Region 1 is not in the registry: no start hub (D-144).
    pub const NO_START_REGION: felt252 = 'no start region';
    // `set_build`'s build and belt: `grimworld_logic::models::sent_build`'s (WPN-01).
    pub use grimworld_logic::models::sent_build::errors::{
        BELT_NOT_IN_PACK, COUNT_WITHOUT_ITEM, DUPLICATE_SKILL, ELITE_SLOT, NOT_A_POTION,
        NO_ATTRIBUTE, NO_SKILL, POINTS, RANK_ABOVE_12, SKILL_NOT_KNOWN, SKILL_PROFESSION,
        TWO_ELITES,
    };
    // `buy_skill`, the hub's skill trainer (design/03, design/15; D-275): one refusal per rule.
    /// Not in the registry: no such skill to sell.
    pub const SKILL_NOT_SOLD: felt252 = 'trainer: no skill';
    pub const SKILL_ALREADY_KNOWN: felt252 = 'trainer: skill known';
    /// The pack's gold is below the skill's price.
    pub const SKILL_PRICE: felt252 = 'trainer: not enough gold';
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

    /// Whether the one item of its pack's equipment (`page` holds it alone, `base` its base) is
    /// its creation kit's weapon, forfeited with the kit at deletion (D-310): an item of the kit's
    /// `BASE` (`weapon`, not 0), worn in the weapon slot (`equipped` holding it alone has the
    /// page's word) or not worn, nothing else worn. Any item of that base counts, as any gold up
    /// to the purse does: the chain does not tell the kit's from another.
    fn forfeits(weapon: u16, base: u16, page: @StoredLanes, equipped: @StoredLanes) -> bool {
        weapon != 0 && base == weapon && (equipped.is_empty() || *equipped.word == *page.word)
    }
}

/// The belt word (`Lanes32`): the potion item of each slot in lanes 0-3, the count to carry in
/// each slot in lane 4, 8 bits a slot (ENG-01 §3.3). Read as its stored word: its seven lanes are
/// not all needed.
#[generate_trait]
pub impl BeltImpl of BeltTrait {
    /// `(items, counts)` of a stored belt, its two limbs decoded in one pass.
    fn read(belt: @StoredLanes) -> ([u32; 4], [u8; 4]) {
        let (low, high) = PackingTrait::split(*belt.word);
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
                LimbTrait::low_field(high, P8.try_into().unwrap()).try_into().unwrap(),
                LimbTrait::byte_at(high, P8), LimbTrait::byte_at(high, P16),
                LimbTrait::byte_at(high, P24),
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

/// `known_skills`: a `Bitmap` of 250 skill ids a page (ENG-01 §3.3).
pub const SKILLS_PER_PAGE: u16 = 250;

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
        let (low, high) = PackingTrait::split(*page.bits);
        if bit < 128 {
            BitTrait::is_set(low, bit)
        } else {
            BitTrait::is_set(high, bit - 128)
        }
    }

    /// The page with bit `bit` (0 to 249) set: an or on the word's two limbs, so that a bit already
    /// set stays set and the page is unchanged. `LIVE` (bit 250) and the stored encoding are kept.
    fn learned(page: Bitmap, bit: u8) -> Bitmap {
        let wide: u256 = page.bits.into();
        let (low, high) = if bit < 128 {
            (wide.low | BitTrait::pow2(bit), wide.high)
        } else {
            (wide.low, wide.high | BitTrait::pow2(bit - 128))
        };
        Bitmap { bits: u256 { low, high }.try_into().unwrap() }
    }

    /// The skills a page knows, counted up to `cap`: one step a skill, each clearing the lowest
    /// set bit. Bound: `cap` steps.
    fn count(page: @Bitmap, cap: u8) -> u8 {
        let (mut low, mut high) = PackingTrait::split(*page.bits);
        let mut count: u8 = 0;
        while count < cap {
            if low != 0 {
                low = low & (low - 1);
            } else if high != 0 {
                high = high & (high - 1);
            } else {
                break;
            }
            count += 1;
        }
        count
    }
}

/// The skill trainer's price of the next skill, by the number of skills known (design/15
/// *Services*: "50 gold for the first skill bought, rising to 1 000 from the 21st, as in the
/// baseline"). The steps between are the baseline's (Guild Wars' skill trainers), adopted by the PM
/// (D-277); every known skill counts (D-278).
const SKILL_PRICES: [u64; 20] = [
    50, 60, 70, 80, 90, 100, 125, 150, 175, 200, 250, 300, 350, 400, 475, 550, 625, 700, 800, 900,
];
/// From the 21st skill on.
pub const LAST_SKILL_PRICE: u64 = 1000;
/// The skills known past which the price no longer rises.
pub const PRICED_SKILLS: u8 = 20;

#[generate_trait]
pub impl SkillTrainerImpl of SkillTrainerTrait {
    /// A new adventurer's purse (D-309): what its first `count` skills cost, bought in a row from
    /// none known; `count` is how many starter skills its profession's `KIT` names, so that the
    /// purse buys that bar and nothing more, priced by this table, never a second constant.
    fn purse(count: u8) -> u64 {
        let mut total: u64 = 0;
        for known in 0..count {
            total += Self::price(known);
        }
        total
    }

    /// The price of a skill when the adventurer knows `known` (capped at `PRICED_SKILLS`).
    fn price(known: u8) -> u64 {
        if known >= PRICED_SKILLS {
            LAST_SKILL_PRICE
        } else {
            *SKILL_PRICES.span()[known.into()]
        }
    }
}

/// The skill trainer's refusals (`buy_skill`), one per rule.
#[generate_trait]
pub impl SkillTrainerAssert of SkillTrainerAssertTrait {
    /// The skill is in the registry's content.
    #[inline(always)]
    fn assert_sold(exists: bool) {
        assert(exists, errors::SKILL_NOT_SOLD);
    }

    /// The adventurer does not know it yet.
    #[inline(always)]
    fn assert_unknown(known: bool) {
        assert(!known, errors::SKILL_ALREADY_KNOWN);
    }

    /// The pack's gold pays the price.
    #[inline(always)]
    fn assert_affordable(gold: u64, price: u64) {
        assert(gold >= price, errors::SKILL_PRICE);
    }
}

/// `equipped`: seven entities, lanes weapon, off-hand, chest, legs, head, hands, feet (ENG-01
/// §3.3).
#[generate_trait]
pub impl EquippedAssert of EquippedAssertTrait {
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

    /// The items worn (`HubStoreTrait::get_equipment`), in lane order: each wearable by the
    /// adventurer and in its lane's slot; then no off-hand (`entities`' lane 1) beside a weapon
    /// held in both hands.
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

    /// D-144: the start hub is region 1's town, read from the registry.
    fn assert_start_region(exists: bool) {
        assert(exists, errors::NO_START_REGION);
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
        PackingTrait::join(low, high)
    }
    fn unpack(value: felt252) -> AdventurerCore {
        let (low, high) = PackingTrait::split(value);
        AdventurerCore {
            account: LimbTrait::low_field(low, P32.try_into().unwrap()).try_into().unwrap(),
            experience: LimbTrait::u32_at(low, P32),
            merit: LimbTrait::u32_at(low, P64),
            level: LimbTrait::byte_at(low, P96),
            rank: LimbTrait::byte_at(low, P104),
            profession: LimbTrait::byte_at(low, P112),
            secondary: LimbTrait::byte_at(low, P120),
            unspent: LimbTrait::low_field(high, P16.try_into().unwrap()).try_into().unwrap(),
            trials_first: LimbTrait::u16_at(high, P16),
            trials_tried: LimbTrait::u16_at(high, P32),
            status: LimbTrait::byte_at(high, P48),
            pack_lanes: LimbTrait::u16_at(high, P56),
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
        PackingTrait::join(
            value.instance.into()
                + value.hub.into() * P64
                + value.last_hub.into() * P80
                + value.inside.into() * P96,
            value.unlocked.into(),
        )
    }
    fn unpack(value: felt252) -> AdventurerPlace {
        let (low, high) = PackingTrait::split(value);
        AdventurerPlace {
            instance: LimbTrait::low_field(low, P64.try_into().unwrap()).try_into().unwrap(),
            hub: LimbTrait::u16_at(low, P64),
            last_hub: LimbTrait::u16_at(low, P80),
            inside: LimbTrait::byte_at(low, P96),
            unlocked: LimbTrait::low_field(high, P64.try_into().unwrap()).try_into().unwrap(),
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
    use grimworld_logic::helpers::packing::{Bitmap, LIVE, Lanes32};
    use starknet::storage_access::StorePacking;
    use super::super::account::PACK;
    use super::super::item::{COMMON, EquipmentTrait, Item, ItemBase, ItemMods, Modifier};
    use super::super::lanes::StoredLanes;
    use super::super::stored_build::NEW_BUILD;
    use super::super::stored_core::StoredCore;
    use super::super::stored_place::{StoredPlace, StoredPlaceTrait};
    use super::{
        ACTIVE, AdventurerCore, AdventurerPlace, AdventurerTrait, BeltAssert, BeltTrait, Build,
        BuildAssert, BuildTrait, EquippedAssert, KnownSkillsTrait, LAST_SKILL_PRICE, NO_ELITE,
        PRICED_SKILLS, SkillTrainerTrait,
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
    #[available_gas(l2_gas: 137939)] // ceil(1.05 × 131370 measured)
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
    #[available_gas(l2_gas: 284949)] // ceil(1.05 × 271380 measured)
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
    #[available_gas(l2_gas: 35322)] // ceil(1.05 × 33640 measured)
    fn test_attributes_above_36_bits_refused() {
        StorePacking::<
            Build, felt252,
        >::pack(Build { bar: [0; 8], attributes: 0x1000000000, elite_slot: 0 });
    }

    #[test]
    #[available_gas(l2_gas: 129087)] // ceil(1.05 × 122940 measured)
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
    #[available_gas(l2_gas: 34010)] // ceil(1.05 × 32390 measured)
    fn test_assert_bar_and_potions() {
        let empty = Build { bar: [0; 8], attributes: 0, elite_slot: NO_ELITE };
        assert(empty.assert_bar(array![].span(), array![].span(), 1, 0) == 0, 'empty bar');
        assert(BeltAssert::assert_potions(array![5].span(), 0, 0) == array![5].span(), 'no potion');
    }

    #[test]
    #[should_panic(expected: 'build: skill not known')]
    #[available_gas(l2_gas: 19635)] // ceil(1.05 × 18700 measured)
    fn test_assert_bar_unknown_refused() {
        let bar = Build { bar: [4, 0, 0, 0, 0, 0, 0, 0], attributes: 0, elite_slot: NO_ELITE };
        bar.assert_bar(array![0, 0].span(), array![false].span(), 1, 0);
    }

    #[test]
    #[should_panic(expected: 'belt: not a potion')]
    #[available_gas(l2_gas: 19572)] // ceil(1.05 × 18640 measured)
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
    #[available_gas(l2_gas: 143273)] // ceil(1.05 × 136450 measured)
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
    #[available_gas(l2_gas: 38294)] // ceil(1.05 × 36470 measured)
    fn test_assert_bar_two_elites_refused() {
        let bar = Build { bar: [4, 5, 0, 0, 0, 0, 0, 0], attributes: 0, elite_slot: 0 };
        let parts = array![skill_part(1, true), 0, skill_part(1, true), 0];
        bar.assert_bar(parts.span(), array![true, true].span(), 1, 0);
    }

    #[test]
    #[should_panic(expected: 'build: elite slot')]
    #[available_gas(l2_gas: 59588)] // ceil(1.05 × 56750 measured)
    fn test_assert_bar_elite_slot_refused() {
        let bar = Build { bar: [4, 5, 0, 0, 0, 0, 0, 0], attributes: 0, elite_slot: 0 };
        let parts = array![skill_part(1, false), 0, skill_part(1, true), 0];
        bar.assert_bar(parts.span(), array![true, true].span(), 1, 0);
    }

    #[test]
    #[should_panic(expected: 'build: skill profession')]
    #[available_gas(l2_gas: 22859)] // ceil(1.05 × 21770 measured)
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
    #[available_gas(l2_gas: 135879)] // ceil(1.05 × 129408 measured)
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
    #[available_gas(l2_gas: 73069)] // ceil(1.05 × 69589 measured)
    fn test_assert_worn_two_hands_refused() {
        let mut equipment = EquipmentTrait::new();
        equipment.add(0, worn(1, 2));
        equipment.add(1, worn(2, 0));
        EquippedAssert::assert_worn(@equipment, 5, array![10, 11, 0, 0, 0, 0, 0].span());
    }

    #[test]
    #[should_panic(expected: 'equipped: wrong slot')]
    #[available_gas(l2_gas: 40723)] // ceil(1.05 × 38783 measured)
    fn test_assert_worn_wrong_slot_refused() {
        let mut equipment = EquipmentTrait::new();
        equipment.add(2, worn(4, 0));
        EquippedAssert::assert_worn(@equipment, 5, array![0, 0, 12, 0, 0, 0, 0].span());
    }

    #[test]
    #[should_panic(expected: 'item: not in the pack')]
    #[available_gas(l2_gas: 35102)] // ceil(1.05 × 33430 measured)
    fn test_assert_worn_not_in_pack_refused() {
        let mut equipment = EquipmentTrait::new();
        equipment.add(2, worn(3, 0));
        EquippedAssert::assert_worn(@equipment, 6, array![0, 0, 12, 0, 0, 0, 0].span());
    }

    // CBT-08a: bit `skill % 250` of page `skill / 250`, in both limbs.
    #[test]
    #[available_gas(l2_gas: 165963)] // ceil(1.05 × 158060 measured)
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
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'build: skill not known')]
    fn test_known_skills_past_page_255() {
        KnownSkillsTrait::at(64000);
    }

    // SKILL-01: a skill learned in either limb, the count capped, the price's steps (design/15:
    // 50 for the first, 1,000 from the 21st; the 20 first cost 6,450 in all, as in the baseline).
    #[test]
    // gas: raised, CNT-01: `SkillTrainerTrait` holds `purse` (D-309), the module's code moved
    #[available_gas(l2_gas: 501431)] // ceil(1.05 × 477553 measured)
    fn test_skill_trainer() {
        let mut page: Bitmap = StorePacking::unpack(0);
        assert(KnownSkillsTrait::count(@page, PRICED_SKILLS) == 0, 'none known');
        for bit in array![0_u8, 127, 128, 249] {
            assert(!KnownSkillsTrait::knows(@page, bit), 'not yet');
            page = KnownSkillsTrait::learned(page, bit);
            assert(KnownSkillsTrait::knows(@page, bit), 'learned');
        }
        let stored: Bitmap = StorePacking::unpack(StorePacking::pack(page));
        assert(KnownSkillsTrait::count(@stored, PRICED_SKILLS) == 4, 'four in both limbs');
        assert(KnownSkillsTrait::count(@stored, 3) == 3, 'capped');
        let full = Bitmap {
            bits: 0x3ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
        };
        assert(
            KnownSkillsTrait::count(@full, PRICED_SKILLS) == PRICED_SKILLS,
            'count stops at the cap',
        );
        let mut total: u64 = 0;
        for known in 0..PRICED_SKILLS {
            let price = SkillTrainerTrait::price(known);
            assert(known == 0 || price > SkillTrainerTrait::price(known - 1), 'rising');
            total += price;
        }
        assert(SkillTrainerTrait::price(0) == 50, 'first 50');
        assert(SkillTrainerTrait::price(19) == 900, '20th 900');
        assert(total == 6450, 'the 20 first');
        assert(SkillTrainerTrait::price(20) == LAST_SKILL_PRICE, '21st 1000');
        assert(SkillTrainerTrait::price(255) == 1000, 'and after');
    }

    // design/03's points against its rule as a loop: 5 a level up to 10, 10 from 11 to 15, 15
    // from 16 to 20, 15 at Tin and 15 at Copper.
    #[test]
    #[available_gas(l2_gas: 304983)] // ceil(1.05 × 290460 measured)
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
    #[available_gas(l2_gas: 93807)] // ceil(1.05 × 89340 measured)
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
