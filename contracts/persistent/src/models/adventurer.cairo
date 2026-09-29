//! An adventurer (design/03): six consecutive slots under its id. Layouts:
//! docs/architecture/ENG-01-interfaces.md, *Hub storage*.

use grimworld_logic::packing::{
    LIVE, Lanes32, P104, P112, P120, P16, P32, P40, P48, P56, P64, P80, P96, byte_at, field, fits, join,
    low_field, split, u16_at, u32_at,
};

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

/// `inside` of a stored `AdventurerPlace` word, without unpacking the other fields.
pub fn is_inside(place: felt252) -> bool {
    let (low, _) = split(place);
    byte_at(low, P96) != 0
}

// Stored words written or changed by arithmetic, without the packers: each is pinned against the
// packer by `test_stored_words` (the packers are the oracle, docs/CAIRO.md §2).

/// The stored `AdventurerCore` of a new adventurer: its account, level 1, its profession, every
/// other field 0 (`ACTIVE`).
pub fn new_core(account: u32, profession: u8) -> felt252 {
    LIVE + account.into() + LEVEL_ONE + profession.into() * PROFESSION_UNIT
}
const LEVEL_ONE: felt252 = 0x1000000000000000000000000;
const PROFESSION_UNIT: felt252 = 0x10000000000000000000000000000;
/// Added to a stored `AdventurerCore` whose status is `ACTIVE`, it becomes `DELETED` (bit 176).
pub const DELETED_MARK: felt252 = 0x100000000000000000000000000000000000000000000;
/// The stored `Build` of a new adventurer: an empty bar, no attribute rank, `NO_ELITE`.
pub const NEW_BUILD: felt252 = 0x4000000000000000000ff000000000000000000000000000000000000000000;
/// A stored `Lanes32` with every lane 0 (the belt and the equipment of a new adventurer).
pub const EMPTY_LANES: felt252 = LIVE;

/// `(account, status, pack_lanes)` of a stored `AdventurerCore`, without unpacking the others.
pub fn core_fields(core: felt252) -> (u32, u8, u16) {
    let (low, high) = split(core);
    (low_field(low, P32.try_into().unwrap()).try_into().unwrap(), byte_at(high, P48), u16_at(high, P56))
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
