//! Equipment is an entity (design/15, *On-chain notes*); everything counted is a balance. Also the
//! grimoire (design/07) and the Rift board (design/17). Layouts:
//! docs/architecture/ENG-01-interfaces.md, *Hub storage*.

use grimworld_logic::packing::{
    P104, P16, P24, P32, P40, P48, P56, P64, P72, P80, P88, byte_at, field, join, low_field, split,
    u16_at, u32_at,
};

/// Item flags (`ItemBase.flags`).
pub const IDENTIFIED: u8 = 1;
pub const PERSONALISED: u8 = 2;
pub const BOSS: u8 = 4;
/// A modifier lifted off an item (design/15): a component, set on another item later.
pub const COMPONENT: u8 = 8;

/// What an item is and who holds it. Written when it drops (unidentified: its modifiers do not
/// exist yet, design/15), when it is crafted or bought, and when it moves.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct ItemBase {
    /// bits 0-15: the equipment base (registry)
    pub base: u16,
    /// bits 16-23: requirement 0-9
    pub requirement: u8,
    /// bits 24-31: 0 common … 3 rare, 4 boss
    pub rarity: u8,
    /// bits 32-39: the level of the goblin that dropped it (base statistics, design/15)
    pub level: u8,
    /// bits 40-47: `IDENTIFIED`, `PERSONALISED`, `BOSS`, `COMPONENT`
    pub flags: u8,
    /// bits 48-63: its look (design/03, D-34)
    pub look: u16,
    /// bits 64-79: its armor set, 0 for none
    pub set: u16,
    /// bits 80-87: `PACK`, `VAULT` or `ESCROW` (models::account)
    pub owner_kind: u8,
    /// bits 88-119: the adventurer, account or lot holding it
    pub owner: u32,
}

pub impl ItemBaseStorePacking of starknet::storage_access::StorePacking<ItemBase, felt252> {
    fn pack(value: ItemBase) -> felt252 {
        join(
            value.base.into()
                + value.requirement.into() * P16
                + value.rarity.into() * P24
                + value.level.into() * P32
                + value.flags.into() * P40
                + value.look.into() * P48
                + value.set.into() * P64
                + value.owner_kind.into() * P80
                + value.owner.into() * P88,
            0,
        )
    }
    fn unpack(value: felt252) -> ItemBase {
        let (low, _) = split(value);
        ItemBase {
            base: low_field(low, P16.try_into().unwrap()).try_into().unwrap(),
            requirement: byte_at(low, P16),
            rarity: byte_at(low, P24),
            level: byte_at(low, P32),
            flags: byte_at(low, P40),
            look: u16_at(low, P48),
            set: u16_at(low, P64),
            owner_kind: byte_at(low, P80),
            owner: u32_at(low, P88),
        }
    }
}

/// A modifier on an item: its registry id and its value.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Modifier {
    pub id: u16,
    pub value: u8,
}

/// Prefix, suffix, inscription, insignia, rune: 24 bits each at bits 0, 24, 48, 72, 96. Written
/// at identification (the draw) and by the enchanter.
#[derive(Copy, Drop, Serde, Debug, PartialEq)]
pub struct ItemMods {
    pub mods: [Modifier; 5],
}

pub impl ItemModsStorePacking of starknet::storage_access::StorePacking<ItemMods, felt252> {
    fn pack(value: ItemMods) -> felt252 {
        let mut low: u128 = 0;
        let mut factor: u128 = 1;
        for m in value.mods.span() {
            low += ((*m.id).into() + (*m.value).into() * P16) * factor;
            factor *= P24;
        }
        join(low, 0)
    }
    fn unpack(value: felt252) -> ItemMods {
        let (low, _) = split(value);
        let mut out: Array<Modifier> = array![];
        let mut rest = low;
        for _ in 0..5_u8 {
            let (next, bits) = DivRem::div_rem(rest, P24.try_into().unwrap());
            out
                .append(
                    Modifier {
                        id: low_field(bits, P16.try_into().unwrap()).try_into().unwrap(),
                        value: byte_at(bits, P16),
                    },
                );
            rest = next;
        }
        ItemMods { mods: [*out[0], *out[1], *out[2], *out[3], *out[4]] }
    }
}

/// Two consecutive slots under an item entity id (ids are handed out by a counter).
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Item {
    pub base: ItemBase,
    pub mods: ItemMods,
}

/// The state of one adventurer's discovery in one book (design/07).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct GrimoireState {
    /// bits 0-15: recipes discovered, bit per recipe of the book
    pub known: u16,
    /// bits 16-63: untried pairs of each of the six signatures, 8 bits each
    pub remaining: u64,
    /// bits 64-127: four hints, 16 bits each (recipe 4 bits, ingredient 4 bits, partners left
    /// 8 bits)
    pub hints: u64,
}

pub impl GrimoireStateStorePacking of starknet::storage_access::StorePacking<
    GrimoireState, felt252,
> {
    fn pack(value: GrimoireState) -> felt252 {
        join(value.known.into() + value.remaining.into() * P16 + value.hints.into() * P64, 0)
    }
    fn unpack(value: felt252) -> GrimoireState {
        let (low, _) = split(value);
        GrimoireState {
            known: low_field(low, P16.try_into().unwrap()).try_into().unwrap(),
            remaining: field(low, P16, 0x1000000000000).try_into().unwrap(),
            hints: field(low, P64, P64).try_into().unwrap(),
        }
    }
}

/// The result of up to 49 pairs of a book, 5 bits each (bit 0 tried, bits 1-4 the recipe + 1, or
/// 0 for a failed brew): pairs 0-24 at bits `5 i`, pairs 25-48 at bits `128 + 5 (i − 25)`. A book
/// of 10 ingredients has 45 pairs: one felt; 11 or 12 ingredients need the second.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Pairs {
    /// Pairs 0-24, 125 bits.
    pub low: u128,
    /// Pairs 25-48, 120 bits.
    pub high: u128,
}

pub impl PairsStorePacking of starknet::storage_access::StorePacking<Pairs, felt252> {
    fn pack(value: Pairs) -> felt252 {
        join(value.low, value.high)
    }
    fn unpack(value: felt252) -> Pairs {
        let (low, high) = split(value);
        Pairs { low, high }
    }
}

/// Three consecutive slots under `(adventurer, book)`.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Grimoire {
    pub state: GrimoireState,
    pub pairs: Pairs,
    pub pairs_more: Pairs,
}

/// Gold of an owner (design/07: an internal balance), `u64` (SPK-11 §6).
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct Gold {
    pub amount: u64,
}

pub impl GoldStorePacking of starknet::storage_access::StorePacking<Gold, felt252> {
    fn pack(value: Gold) -> felt252 {
        join(value.amount.into(), 0)
    }
    fn unpack(value: felt252) -> Gold {
        let (low, _) = split(value);
        Gold { amount: low_field(low, P64.try_into().unwrap()).try_into().unwrap() }
    }
}

/// An account's Rifts of the day (design/17): the identities derived from one Fate draw by the
/// first board action of the day, and which are cleared.
#[derive(Copy, Drop, Serde, Debug, PartialEq, Default)]
pub struct RiftBoard {
    /// bits 0-31: the day (UTC days since the epoch)
    pub day: u32,
    /// bits 32-39: bit `i`, Rift `i` cleared (Rift 4 opens with one bit, the Red Rift with two)
    pub cleared: u8,
    /// bits 40-119: five identities of 16 bits (grade 4, biome 4, floors 4, size 4)
    pub rifts: [u16; 5],
}

pub impl RiftBoardStorePacking of starknet::storage_access::StorePacking<RiftBoard, felt252> {
    fn pack(value: RiftBoard) -> felt252 {
        let [a, b, c, d, e] = value.rifts;
        join(
            value.day.into()
                + value.cleared.into() * P32
                + a.into() * P40
                + b.into() * P56
                + c.into() * P72
                + d.into() * P88
                + e.into() * P104,
            0,
        )
    }
    fn unpack(value: felt252) -> RiftBoard {
        let (low, _) = split(value);
        RiftBoard {
            day: low_field(low, P32.try_into().unwrap()).try_into().unwrap(),
            cleared: byte_at(low, P32),
            rifts: [
                u16_at(low, P40), u16_at(low, P56), u16_at(low, P72),
                u16_at(low, P88), u16_at(low, P104),
            ],
        }
    }
}
