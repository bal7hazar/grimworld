//! Equipment is an entity (design/15, *On-chain notes*); everything counted is a balance. Also the
//! grimoire (design/07) and the Rift board (design/17). Layouts:
//! docs/architecture/ENG-01-interfaces.md, *Hub storage*.

use grimworld_logic::content::MODIFIER;
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

/// The items an adventurer wears, as `set_build` checks them and the flattening reads them: each
/// one's lane and `ItemBase`, for the equipment's checks; each as the flattening reads it (`Worn`,
/// with its `ItemMods`); the distinct modifier ids they hold, in the order met; whether the weapon
/// is personalised (`ItemBase.flags`). Filled one item at a time as the store reads them
/// (`HubStoreTrait::get_equipment`), so that no item is copied. Bound: 7 lanes, 5 modifiers an
/// item.
#[derive(Drop)]
pub struct Equipment {
    pub bases: Array<(u32, ItemBase)>,
    pub worn: Array<Worn>,
    pub modifiers: Array<u16>,
    pub personalised: bool,
}

#[generate_trait]
pub impl EquipmentImpl of EquipmentTrait {
    #[inline(always)]
    fn new() -> Equipment {
        Equipment { bases: array![], worn: array![], modifiers: array![], personalised: false }
    }

    /// The item worn in `lane`, the lanes added in their order.
    #[inline(always)]
    fn add(ref self: Equipment, lane: u32, item: Item) {
        let item_worn = item.mods.worn(lane.try_into().unwrap(), item.base.slot);
        for id in item_worn.ids.span() {
            let id = *id;
            if id == 0 {
                continue;
            }
            let mut seen = false;
            for other in self.modifiers.span() {
                if *other == id {
                    seen = true;
                }
            }
            if !seen {
                self.modifiers.append(id);
            }
        }
        if lane == 0 {
            self.personalised = item.base.flags & PERSONALISED != 0;
        }
        self.bases.append((lane, item.base));
        self.worn.append(item_worn);
    }

    /// The distinct modifiers worn as `Registry.bundle` requests (`MODIFIER`), appended to
    /// `requests` in the order met.
    fn request(self: @Equipment, ref requests: Array<(u8, u32)>) {
        for id in self.modifiers.span() {
            requests.append((MODIFIER, (*id).into()));
        }
    }
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

#[generate_trait]
pub impl GoldImpl of GoldTrait {
    /// `amount` more (a report's gold); past a `u64` the addition refuses, as before.
    #[inline(always)]
    fn credited(self: Gold, amount: u64) -> Gold {
        Gold { amount: self.amount + amount }
    }
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

// The item's, the grimoire's, gold's and the Rift board's layouts (ENG-01 §3.3); the equipment
// read for `set_build`.
#[cfg(test)]
mod tests {
    use grimworld_logic::content::MODIFIER;
    use grimworld_logic::models::base::{BaseTrait, slot};
    use grimworld_logic::packing::LIVE;
    use starknet::storage_access::StorePacking;
    use super::super::account::PACK;
    use super::{
        Equipment, EquipmentTrait, Gold, GoldTrait, Grimoire, GrimoireState, IDENTIFIED, Item,
        ItemBase, ItemBaseTrait, ItemMods, Modifier, PERSONALISED, Pairs, RiftBoard,
    };

    #[test]
    #[available_gas(l2_gas: 363636)] // ceil(1.05 × 346320 measured)
    fn test_item_grimoire_rift_layout() {
        let base = ItemBase {
            base: 0xFFFF,
            requirement: 9,
            rarity: 4,
            level: 28,
            flags: 15,
            look: 0xFFFF,
            set: 0xFFFF,
            owner_kind: 3,
            owner: 0xFFFFFFFF,
            slot: 15,
            hands: 15,
        };
        let word = StorePacking::<ItemBase, felt252>::pack(base);
        assert(StorePacking::<ItemBase, felt252>::unpack(word) == base, 'base trip');
        let owner = ItemBase { owner: 1, ..Default::default() };
        assert(
            StorePacking::<ItemBase, felt252>::pack(owner) == 0x10000000000000000000000 + LIVE,
            'owner at bit 88',
        );

        let full = Modifier { id: 0xFFFF, value: 0xFF };
        let mods = ItemMods { mods: [full, Modifier { id: 1, value: 2 }, full, full, full] };
        let word = StorePacking::<ItemMods, felt252>::pack(mods);
        assert(StorePacking::<ItemMods, felt252>::unpack(word) == mods, 'mods trip');

        let state = GrimoireState {
            known: 0xFFFF, remaining: 0xFFFFFFFFFFFF, hints: 0xFFFFFFFFFFFFFFFF,
        };
        let word = StorePacking::<GrimoireState, felt252>::pack(state);
        assert(StorePacking::<GrimoireState, felt252>::unpack(word) == state, 'grimoire trip');
        let pairs = Pairs {
            low: 0x1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, high: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
        };
        let word = StorePacking::<Pairs, felt252>::pack(pairs);
        assert(StorePacking::<Pairs, felt252>::unpack(word) == pairs, 'pairs trip');

        let gold = Gold { amount: 0xFFFFFFFFFFFFFFFF };
        let word = StorePacking::<Gold, felt252>::pack(gold);
        assert(StorePacking::<Gold, felt252>::unpack(word) == gold, 'gold trip');
        assert(StorePacking::<Gold, felt252>::pack(Gold { amount: 0 }) == LIVE, 'no gold is not 0');

        assert(GoldTrait::credited(gold, 0) == gold, 'credited 0');
        assert(Gold { amount: 2 }.credited(5) == Gold { amount: 7 }, 'credited');
        assert(starknet::Store::<Item>::size() == 2, 'item: 2 slots');
        assert(starknet::Store::<Grimoire>::size() == 3, 'grimoire: 3 slots');

        let board = RiftBoard { day: 20725, cleared: 0x1F, rifts: [1, 2, 3, 4, 0xFFFF] };
        let word = StorePacking::<RiftBoard, felt252>::pack(board);
        assert(StorePacking::<RiftBoard, felt252>::unpack(word) == board, 'rift trip');
    }

    #[test]
    #[should_panic(expected: 'packing: pairs 25-48 overflow')]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    fn test_pairs_overflow_refused() {
        StorePacking::<
            Pairs, felt252,
        >::pack(Pairs { low: 0, high: 0x1000000000000000000000000000000 });
    }

    // CBT-08a, D-158: `ItemBase.slot` at bit 120 and `hands` at 124, 4 bits each, copied from the
    // `BASE` record by the constructor every creator of an item calls.
    #[test]
    #[available_gas(l2_gas: 189315)] // ceil(1.05 × 180300 measured)
    fn test_item_slot_and_hands() {
        let one = ItemBase { slot: 1, ..Default::default() };
        assert(
            StorePacking::<ItemBase, felt252>::pack(one) == 0x1000000000000000000000000000000
                + LIVE,
            'slot at bit 120',
        );
        let two = ItemBase { hands: 1, ..Default::default() };
        assert(
            StorePacking::<ItemBase, felt252>::pack(two) == 0x10000000000000000000000000000000
                + LIVE,
            'hands at bit 124',
        );
        let maul = BaseTrait::new(slot::WEAPON, 2);
        let item = ItemBaseTrait::new(7, @maul, 9, 1, 20, IDENTIFIED, 3, 0, PACK, 5);
        let expected = ItemBase {
            base: 7,
            requirement: 9,
            rarity: 1,
            level: 20,
            flags: IDENTIFIED,
            look: 3,
            set: 0,
            owner_kind: PACK,
            owner: 5,
            slot: slot::WEAPON,
            hands: 2,
        };
        assert(item == expected, 'copied from the base');
        assert(item.is_two_handed(), 'two hands');
        let feet = ItemBaseTrait::new(8, @BaseTrait::new(slot::FEET, 0), 0, 0, 1, 0, 0, 0, PACK, 5);
        assert(feet.slot == slot::FEET && feet.hands == 0 && !feet.is_two_handed(), 'feet');
        let word = StorePacking::<ItemBase, felt252>::pack(item);
        assert(StorePacking::<ItemBase, felt252>::unpack(word) == item, 'round trip');
    }

    #[test]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    #[should_panic(expected: 'packing: slot above 4 b')]
    fn test_item_slot_too_wide() {
        StorePacking::<ItemBase, felt252>::pack(ItemBase { slot: 16, ..Default::default() });
    }

    #[test]
    #[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
    #[should_panic(expected: 'packing: hands above 4 b')]
    fn test_item_hands_too_wide() {
        StorePacking::<ItemBase, felt252>::pack(ItemBase { hands: 16, ..Default::default() });
    }

    // The items worn as `set_build` reads them: lanes and bases in lane order, the distinct
    // modifiers in the order met, the weapon's personalisation.
    #[test]
    #[available_gas(l2_gas: 158945)] // ceil(1.05 × 151376 measured)
    fn test_equipment() {
        let none = Modifier { id: 0, value: 0 };
        let weapon = Item {
            base: ItemBase { slot: 1, flags: PERSONALISED, ..Default::default() },
            mods: ItemMods {
                mods: [
                    Modifier { id: 4, value: 1 }, Modifier { id: 9, value: 2 }, none, none, none,
                ],
            },
        };
        let feet = Item {
            base: ItemBase { slot: 7, ..Default::default() },
            mods: ItemMods {
                mods: [
                    Modifier { id: 9, value: 3 }, none, none, none, Modifier { id: 2, value: 1 },
                ],
            },
        };
        let mut equipment = EquipmentTrait::new();
        equipment.add(0, weapon);
        equipment.add(6, feet);
        let Equipment { bases, worn, modifiers, personalised } = equipment;
        assert(bases == array![(0, weapon.base), (6, feet.base)], 'bases');
        assert(worn.len() == 2 && *worn[1].lane == 6 && *worn[1].slot == 7, 'worn');
        assert(*worn[1].values.span()[0] == 3, 'values');
        assert(modifiers == array![4, 9, 2], 'distinct modifiers');
        assert(personalised, 'personalised');
        assert(!EquipmentTrait::new().personalised, 'nothing worn');
        let mut equipment = EquipmentTrait::new();
        equipment.add(0, weapon);
        let mut requests = array![(9, 1)];
        equipment.request(ref requests);
        assert(requests == array![(9, 1), (MODIFIER, 4), (MODIFIER, 9)], 'modifier requests');
    }
}
