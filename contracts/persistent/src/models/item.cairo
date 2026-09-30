//! Equipment is an entity (design/15, *On-chain notes*); everything counted is a balance. Also the
//! grimoire (design/07) and the Rift board (design/17). Layouts:
//! docs/architecture/ENG-01-interfaces.md, *Hub storage*.

use grimworld_logic::models::base::Base;
use grimworld_logic::packing::{
    P104, P120, P16, P24, P32, P4, P40, P48, P56, P64, P72, P80, P88, byte_at, field, fits, join,
    low_field, split, u16_at, u32_at,
};
use grimworld_logic::snapshot::Worn;
use super::account::PACK;

/// `ItemBase.hands` sits at bit 124.
const P124: u128 = 0x10000000000000000000000000000000;

/// Item flags (`ItemBase.flags`).
pub const IDENTIFIED: u8 = 1;
pub const PERSONALISED: u8 = 2;
pub const BOSS: u8 = 4;
/// A modifier lifted off an item (design/15): a component, set on another item later.
pub const COMPONENT: u8 = 8;

/// `ItemBase.rarity` of a common item: no modifier, so nothing to identify (design/15, *Rarity*).
pub const COMMON: u8 = 0;

pub mod errors {
    /// Not in the adventurer's pack (another owner, the vault, escrow, or no such entity).
    pub const NOT_IN_PACK: felt252 = 'item: not in the pack';
    /// A modifier lifted off an item: a component, not equipment.
    pub const A_COMPONENT: felt252 = 'item: a component';
    /// Fine or above and not identified: identifying is "needed to equip it" (design/15).
    pub const UNIDENTIFIED: felt252 = 'item: unidentified';
}

#[generate_trait]
pub impl ItemBaseImpl of ItemBaseTrait {
    /// An item as its creator writes it (loot, a craft, a shop, a quest, a collector: design/15):
    /// the slot and the hands of its `BASE` record are copied into it, so that `set_build` reads
    /// no registry record (D-158). Every writer of a new entity calls this.
    fn new(
        base: u16,
        record: @Base,
        requirement: u8,
        rarity: u8,
        level: u8,
        flags: u8,
        look: u16,
        set: u16,
        owner_kind: u8,
        owner: u32,
    ) -> ItemBase {
        ItemBase {
            base,
            requirement,
            rarity,
            level,
            flags,
            look,
            set,
            owner_kind,
            owner,
            slot: *record.slot,
            hands: *record.hands,
        }
    }

    /// A weapon held in both hands: nothing goes in the off-hand (design/15, *Weapons*).
    #[inline(always)]
    fn is_two_handed(self: @ItemBase) -> bool {
        *self.hands == 2
    }
}

#[generate_trait]
pub impl ItemBaseAssert of ItemBaseAssertTrait {
    /// What an adventurer may wear (design/15): an item of its own pack (an entity never written
    /// has owner kind 0), not a component, identified unless common. The requirement is not a
    /// refusal: "anyone can hold any weapon", below it the damage is divided by 3 (design/15,
    /// *Requirement*), which the snapshot applies.
    fn assert_wearable(self: @ItemBase, adventurer_id: u32) {
        assert(*self.owner_kind == PACK && *self.owner == adventurer_id, errors::NOT_IN_PACK);
        assert(*self.flags & COMPONENT == 0, errors::A_COMPONENT);
        assert(*self.rarity == COMMON || *self.flags & IDENTIFIED != 0, errors::UNIDENTIFIED);
    }
}

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
    /// bits 88-119: the adventurer or account holding it; 0 in escrow (the lot names the entity)
    pub owner: u32,
    /// bits 120-123: its base's slot, copied from the `BASE` record at creation (D-158):
    /// `grimworld_logic::models::base::slot`, 0 for an item that is not worn (a component)
    pub slot: u8,
    /// bits 124-127: its base's hands, copied likewise: 1 or 2 on a weapon, 0 elsewhere
    pub hands: u8,
}

pub impl ItemBaseStorePacking of starknet::storage_access::StorePacking<ItemBase, felt252> {
    fn pack(value: ItemBase) -> felt252 {
        fits(value.slot.into(), P4, 'packing: slot above 4 b');
        fits(value.hands.into(), P4, 'packing: hands above 4 b');
        join(
            value.base.into()
                + value.requirement.into() * P16
                + value.rarity.into() * P24
                + value.level.into() * P32
                + value.flags.into() * P40
                + value.look.into() * P48
                + value.set.into() * P64
                + value.owner_kind.into() * P80
                + value.owner.into() * P88
                + value.slot.into() * P120
                + value.hands.into() * P124,
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
            slot: field(low, P120, P4).try_into().unwrap(),
            hands: field(low, P124, P4).try_into().unwrap(),
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

#[generate_trait]
pub impl ItemModsImpl of ItemModsTrait {
    /// The item as the flattening reads it (`grimworld_logic::snapshot::Worn`): its lane of
    /// `equipped`, its slot, each modifier's id (0 for an empty slot) and rolled value, in
    /// `ItemMods`' order.
    fn worn(self: @ItemMods, lane: u8, slot: u8) -> Worn {
        let [a, b, c, d, e] = *self.mods;
        Worn {
            lane,
            slot,
            ids: [a.id, b.id, c.id, d.id, e.id],
            values: [a.value, b.value, c.value, d.value, e.value],
        }
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
        fits(value.remaining.into(), P48, 'packing: remaining above 48 b');
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
        fits(value.low, 0x20000000000000000000000000000000, 'packing: pairs 0-24 overflow');
        fits(value.high, 0x1000000000000000000000000000000, 'packing: pairs 25-48 overflow');
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
                u16_at(low, P40), u16_at(low, P56), u16_at(low, P72), u16_at(low, P88),
                u16_at(low, P104),
            ],
        }
    }
}
