//! An adventurer (design/03): six consecutive slots under its id. Layouts:
//! docs/architecture/ENG-01-interfaces.md, *Hub storage*.

use grimworld_logic::packing::{
    LIVE, Lanes32, P104, P112, P120, P16, P24, P32, P40, P48, P56, P64, P8, P80, P96, byte_at,
    field, fits, join, low_field, split, u16_at, u32_at,
};
use starknet::ContractAddress;

/// `AdventurerCore.status`: an adventurer is never zeroed; deletion marks it (design/03, D-33).
pub const ACTIVE: u8 = 0;
pub const DELETED: u8 = 1;
/// `Build.elite_slot` when no elite skill is on the bar.
pub const NO_ELITE: u8 = 255;
/// Offsets of the words of `Adventurer` from its address, for a read of one stored word.
pub const CORE_WORD: u8 = 0;
pub const PLACE_WORD: u8 = 1;
pub const BUILD_WORD: u8 = 2;
pub const BELT_WORD: u8 = 3;
pub const EQUIPPED_WORD: u8 = 4;
pub const NAME_WORD: u8 = 5;

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
}

// Stored words written or read by arithmetic, without the packers: each function below is pinned
// against the packer by `test_stored_words` (the packers are the oracle, docs/CAIRO.md §2). They
// take and return the stored word, since unpacking and packing it is what they save.

const LEVEL_ONE: felt252 = 0x1000000000000000000000000;
const PROFESSION_UNIT: felt252 = 0x10000000000000000000000000000;
/// Added to a stored `AdventurerCore` whose status is `ACTIVE`, it becomes `DELETED` (bit 176).
pub const DELETED_MARK: felt252 = 0x100000000000000000000000000000000000000000000;
/// The stored `Build` of a new adventurer: an empty bar, no attribute rank, `NO_ELITE`.
pub const NEW_BUILD: felt252 = 0x4000000000000000000ff000000000000000000000000000000000000000000;
/// A stored `Lanes32` with every lane 0 (the belt and the equipment of a new adventurer).
pub const EMPTY_LANES: felt252 = LIVE;

#[generate_trait]
pub impl AdventurerCoreImpl of AdventurerCoreTrait {
    /// The stored core of a new adventurer: its account, level 1, its profession, every other
    /// field 0 (`ACTIVE`).
    fn new(account: u32, profession: u8) -> felt252 {
        LIVE + account.into() + LEVEL_ONE + profession.into() * PROFESSION_UNIT
    }

    /// `(account, status, pack_lanes)` of a stored core, without unpacking the others.
    fn fields(core: felt252) -> (u32, u8, u16) {
        let (low, high) = split(core);
        (
            low_field(low, P32.try_into().unwrap()).try_into().unwrap(),
            byte_at(high, P48),
            u16_at(high, P56),
        )
    }

    /// The stored core of an `ACTIVE` adventurer, marked `DELETED`; every other field kept.
    fn deleted(core: felt252) -> felt252 {
        core + DELETED_MARK
    }

    /// `(experience, level, rank, profession)` of a stored core.
    fn profile(core: felt252) -> (u32, u8, u8, u8) {
        let (low, _) = split(core);
        (u32_at(low, P32), byte_at(low, P96), byte_at(low, P104), byte_at(low, P112))
    }

    /// The stored core with `filled` pack lanes more and `emptied` fewer (`pack_lanes`, bits
    /// 184-199): the balance changes that fill or empty a lane keep it (ENG-01 fix loop 1, F-5).
    fn with_pack_lanes(core: felt252, filled: u16, emptied: u16) -> felt252 {
        core + filled.into() * PACK_LANES_UNIT - emptied.into() * PACK_LANES_UNIT
    }

    /// The stored core with `amount` experience more (bits 32-63), refused past a `u32`. What a
    /// level needs is design/03's rule for a later lot: the level is not raised here (escalated in
    /// ENG-06's report).
    fn with_experience(core: felt252, amount: u32) -> felt252 {
        let (experience, _, _, _) = Self::profile(core);
        let total: u64 = experience.into() + amount.into();
        assert(total <= 0xFFFFFFFF, errors::EXPERIENCE_OVERFLOW);
        core + amount.into() * EXPERIENCE_UNIT
    }
}

/// `AdventurerCore.pack_lanes` (bit 184) and `experience` (bit 32) as units of the stored word.
const PACK_LANES_UNIT: felt252 = 0x10000000000000000000000000000000000000000000000;
const EXPERIENCE_UNIT: felt252 = 0x100000000;

/// A stored `AdventurerPlace` read and changed by arithmetic (pinned against the packer by
/// `test_place_words`): entering an instance, moving to the next one, being in a hub, unlocking
/// one.
#[generate_trait]
pub impl AdventurerPlaceImpl of AdventurerPlaceTrait {
    /// `inside` of a stored place, without unpacking the other fields.
    fn is_inside(place: felt252) -> bool {
        let (low, _) = split(place);
        byte_at(low, P96) != 0
    }

    /// `(instance, hub, last hub, inside)` of a stored place.
    fn fields(place: felt252) -> (u64, u16, u16, bool) {
        let (low, _) = split(place);
        (
            low_field(low, P64.try_into().unwrap()).try_into().unwrap(),
            u16_at(low, P64),
            u16_at(low, P80),
            byte_at(low, P96) != 0,
        )
    }

    /// The place of a new adventurer: in `hub`, its last hub, `hub` unlocked (D-144: region 1's
    /// town, unlocked from creation).
    fn new(hub: u16) -> felt252 {
        join(hub.into() * P64 + hub.into() * P80, Self::bit(hub))
    }

    /// Inside `instance`, entered from its hub: `hub` 0, `last_hub` the hub it left, `inside` 1.
    fn entered(place: felt252, instance: u64) -> felt252 {
        let (low, high) = split(place);
        join(instance.into() + u16_at(low, P64).into() * P80 + P96, high)
    }

    /// Still inside, its instance now `instance` (a gate to another location, D-02).
    fn moved(place: felt252, instance: u64) -> felt252 {
        let (low, high) = split(place);
        let (above, _) = DivRem::div_rem(low, P64.try_into().unwrap());
        join(above * P64 + instance.into(), high)
    }

    /// In `hub`, which is also its last hub: no instance, not inside.
    fn located(place: felt252, hub: u16) -> felt252 {
        let (_, high) = split(place);
        join(hub.into() * P64 + hub.into() * P80, high)
    }

    /// `hub` unlocked for map travel (design/01: reaching a hub gate unlocks the hub).
    fn unlocked(place: felt252, hub: u16) -> felt252 {
        let (low, high) = split(place);
        join(low, high | Self::bit(hub))
    }

    fn is_unlocked(place: felt252, hub: u16) -> bool {
        let (_, high) = split(place);
        hub < 64 && high & Self::bit(hub) != 0
    }

    /// Bit `hub` of `unlocked`: a table (docs/CAIRO.md §3); a hub id of 64 or more is refused.
    fn bit(hub: u16) -> u128 {
        match hub {
            0 => 0x1,
            1 => 0x2,
            2 => 0x4,
            3 => 0x8,
            4 => 0x10,
            5 => 0x20,
            6 => 0x40,
            7 => 0x80,
            8 => 0x100,
            9 => 0x200,
            10 => 0x400,
            11 => 0x800,
            12 => 0x1000,
            13 => 0x2000,
            14 => 0x4000,
            15 => 0x8000,
            16 => 0x10000,
            17 => 0x20000,
            18 => 0x40000,
            19 => 0x80000,
            20 => 0x100000,
            21 => 0x200000,
            22 => 0x400000,
            23 => 0x800000,
            24 => 0x1000000,
            25 => 0x2000000,
            26 => 0x4000000,
            27 => 0x8000000,
            28 => 0x10000000,
            29 => 0x20000000,
            30 => 0x40000000,
            31 => 0x80000000,
            32 => 0x100000000,
            33 => 0x200000000,
            34 => 0x400000000,
            35 => 0x800000000,
            36 => 0x1000000000,
            37 => 0x2000000000,
            38 => 0x4000000000,
            39 => 0x8000000000,
            40 => 0x10000000000,
            41 => 0x20000000000,
            42 => 0x40000000000,
            43 => 0x80000000000,
            44 => 0x100000000000,
            45 => 0x200000000000,
            46 => 0x400000000000,
            47 => 0x800000000000,
            48 => 0x1000000000000,
            49 => 0x2000000000000,
            50 => 0x4000000000000,
            51 => 0x8000000000000,
            52 => 0x10000000000000,
            53 => 0x20000000000000,
            54 => 0x40000000000000,
            55 => 0x80000000000000,
            56 => 0x100000000000000,
            57 => 0x200000000000000,
            58 => 0x400000000000000,
            59 => 0x800000000000000,
            60 => 0x1000000000000000,
            61 => 0x2000000000000000,
            62 => 0x4000000000000000,
            63 => 0x8000000000000000,
            _ => core::panic_with_felt252(errors::HUB_ABOVE_63),
        }
    }
}

/// The belt word (`Lanes32`): the potion item of each slot in lanes 0-3, the count to carry in
/// each slot in lane 4, 8 bits a slot (ENG-01 §3.3).
#[generate_trait]
pub impl BeltImpl of BeltTrait {
    /// `(items, counts)` of a stored belt word.
    fn read(belt: felt252) -> ([u32; 4], [u8; 4]) {
        let (low, high) = split(belt);
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
}

#[generate_trait]
pub impl AdventurerAssert of AdventurerAssertTrait {
    /// A name is not empty (D-32).
    fn assert_valid_name(name: felt252) {
        assert(name != 0, errors::EMPTY_NAME);
    }

    /// The ownership check of every entrypoint that names an adventurer (ADR-0007, *Access
    /// control*; ENG-01 §1.2), from its stored core and place and its account's owner: it exists,
    /// the caller owns its account, it is not deleted, and it is in a hub (not inside).
    fn assert_owned_in_hub(
        account_id: u32,
        status: u8,
        place: felt252,
        owner: ContractAddress,
        caller: ContractAddress,
    ) {
        assert(account_id != 0, errors::NO_ADVENTURER);
        assert(owner == caller, errors::NOT_OWNER);
        assert(status != DELETED, errors::ADVENTURER_DELETED);
        assert(!AdventurerPlaceTrait::is_inside(place), errors::NOT_IN_HUB);
    }

    /// "Its inventory emptied" (design/03, D-33), each from one stored word: the pack's balance
    /// lanes, page 0 of its equipment list (compact: empty when page 0 is), what it wears, its
    /// gold. A word is empty when all its fields are 0: never written (0), or `LIVE` alone.
    fn assert_emptied(pack_lanes: u16, pack_page: felt252, equipped: felt252, gold: felt252) {
        assert(pack_lanes == 0, errors::PACK_HOLDS_ITEMS);
        assert(pack_page == 0 || pack_page == LIVE, errors::PACK_HOLDS_EQUIPMENT);
        assert(equipped == 0 || equipped == LIVE, errors::WEARS_EQUIPMENT);
        assert(gold == 0 || gold == LIVE, errors::PACK_HOLDS_GOLD);
    }

    /// Map travel goes to an unlocked hub (design/01 *Connectivity*).
    fn assert_unlocked(place: felt252, hub: u16) {
        assert(AdventurerPlaceTrait::is_unlocked(place, hub), errors::NOT_UNLOCKED);
    }

    /// D-144: the start hub is region 1's town, read from the registry.
    fn assert_start_region(exists: bool) {
        assert(exists, errors::NO_START_REGION);
    }

    /// A report is about the instance its first contributor is inside (ENG-01 §6).
    fn assert_in_instance(place: felt252, instance: u64) {
        let (current, _, _, inside) = AdventurerPlaceTrait::fields(place);
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
