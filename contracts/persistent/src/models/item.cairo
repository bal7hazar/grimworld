//! Equipment is an entity (design/15, *On-chain notes*); everything counted is a balance. Also the
//! grimoire (design/07) and the Rift board (design/17). Layouts:
//! docs/architecture/ENG-01-interfaces.md, *Hub storage*.

use grimworld_logic::helpers::packing::{
    LIVE, LimbTrait, P104, P120, P16, P24, P32, P4, P40, P48, P56, P64, P72, P80, P88,
    PackingAssert, PackingTrait, TWO_POW_128,
};
use grimworld_logic::models::base::{Base, BasePartTrait, BaseTrait, Weapon, WeaponTrait};
use grimworld_logic::models::worn::Worn;
use grimworld_logic::types::content::MODIFIER;
use super::account::PACK;
use super::lanes::{StoredLanes, StoredLanesTrait};

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

/// Pages of a pack's equipment list (ENG-01 §3.3: 20 slots + 5 per bag, at most 4 pages of 7).
pub const PACK_PAGES: u8 = 4;

pub mod errors {
    /// Not in the adventurer's pack (another owner, the vault, escrow, or no such entity).
    pub const NOT_IN_PACK: felt252 = 'item: not in the pack';
    /// Every lane of the pack's equipment list is taken (`PACK_PAGES` pages).
    pub const PACK_FULL: felt252 = 'item: pack full';
    /// A modifier lifted off an item: a component, not equipment.
    pub const A_COMPONENT: felt252 = 'item: a component';
    /// Fine or above and not identified: identifying is "needed to equip it" (design/15).
    pub const UNIDENTIFIED: felt252 = 'item: unidentified';
}

#[generate_trait]
pub impl ItemBaseImpl of ItemBaseTrait {
    /// An item as its creator writes it (loot, a craft, a shop, a quest, a collector, a creation
    /// kit: design/15, D-309): the slot, the hands and the weapon of its `BASE` record, the damage
    /// taken at the item's requirement (`BaseTrait::at`), are copied into it, so that `set_build`
    /// reads no registry record (D-158, WPN-01). Every writer of a new entity calls this.
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
            weapon: record.at(requirement).pack(),
        }
    }

    /// A weapon held in both hands: nothing goes in the off-hand (design/15, *Weapons*).
    #[inline(always)]
    fn is_two_handed(self: @ItemBase) -> bool {
        *self.hands == 2
    }

    /// Its weapon, decoded (all 0 for an item that is not a weapon).
    #[inline(always)]
    fn weapon(self: @ItemBase) -> Weapon {
        WeaponTrait::unpack(*self.weapon)
    }

    /// The item held by nobody, its record kept (an entity id is never reused): a creation kit's
    /// weapon forfeited when its adventurer is deleted (D-310).
    #[inline(always)]
    fn forfeited(self: ItemBase) -> ItemBase {
        ItemBase { owner_kind: 0, owner: 0, ..self }
    }
}

/// `ItemBase` as stored: its word, `LIVE` set, built and changed by arithmetic on the two paths
/// that need no other field, the creation of an item from its `BASE` record's part 0 and the
/// forfeit of a kit's weapon (WPN-01, D-310), where the packer would decode and encode every
/// field. `ItemBase` and its packer stay the layout and the oracle: each method is pinned against
/// them in the tests. Only the store reads and writes it (`HubStoreTrait::create_item`).
#[derive(Copy, Drop, Debug, PartialEq)]
pub struct StoredItemBase {
    pub word: felt252,
}

#[generate_trait]
pub impl StoredItemBaseImpl of StoredItemBaseTrait {
    /// `ItemBaseTrait::new`'s word for an item at level 0 with no flag, look or set, its slot,
    /// hands and weapon read from its `BASE` record's `part` 0 (`BasePartTrait::copied`); the
    /// registry checked the record (slot at most 7, hands at most 2), so every field fits.
    fn new(
        base: u16, part: felt252, requirement: u8, rarity: u8, owner_kind: u8, owner: u32,
    ) -> StoredItemBase {
        let (slot, hands, weapon) = BasePartTrait::copied(part, requirement);
        let low: felt252 = base.into()
            + requirement.into() * P16.into()
            + rarity.into() * P24.into()
            + owner_kind.into() * P80.into()
            + owner.into() * P88.into()
            + slot.into() * P120.into()
            + hands.into() * P124.into();
        StoredItemBase { word: low + weapon.into() * TWO_POW_128 + LIVE }
    }

    /// Its base, bits 0-15.
    #[inline(always)]
    fn base(self: @StoredItemBase) -> u16 {
        let (low, _) = PackingTrait::limbs(*self.word);
        LimbTrait::low_field(low, P16.try_into().unwrap()).try_into().unwrap()
    }

    /// `ItemBaseTrait::forfeited`'s word for an item in `adventurer_id`'s pack: owner kind
    /// (`PACK`) and owner (bits 80-119) cleared. The caller knows the pack holds it.
    #[inline(always)]
    fn forfeited(self: StoredItemBase, adventurer_id: u32) -> StoredItemBase {
        let holder: felt252 = PACK.into() * P80.into() + adventurer_id.into() * P88.into();
        StoredItemBase { word: self.word - holder }
    }
}

/// A pack's equipment list (`packs[(adventurer, page)]`, ENG-01 §3.3): a compact list of entity
/// ids, seven a page, so its first empty lane is its end.
#[generate_trait]
pub impl PackListImpl of PackListTrait {
    /// The first empty lane of a page, if it has one (a page never written has lane 0).
    fn free_lane(page: @StoredLanes) -> Option<u8> {
        let lanes = page.decoded().lanes.span();
        for lane in 0..7_u8 {
            if *lanes[lane.into()] == 0 {
                return Option::Some(lane);
            }
        }
        Option::None
    }

    /// The entity a page holds alone, in lane 0 (a compact list's only entry), if it does: its
    /// word is `LIVE` plus the id. `equipped` holding only a weapon has the same word.
    fn alone(page: @StoredLanes) -> Option<u32> {
        let (low, high) = PackingTrait::split(*page.word);
        if high != 0 || low == 0 || low >= P32 {
            return Option::None;
        }
        Option::Some(low.try_into().unwrap())
    }
}

#[generate_trait]
pub impl PackListAssert of PackListAssertTrait {
    /// An append reaches a page of the list (`PACK_PAGES`).
    #[inline(always)]
    fn assert_room(page: u8) {
        assert(page < PACK_PAGES, errors::PACK_FULL);
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
    /// bits 128-175: its base's weapon at its requirement, copied likewise (WPN-01), as
    /// `WeaponTrait::pack` lays it out (class, damage, ticks, range, damage type, attribute, 8
    /// bits each; 0 elsewhere). Kept packed: `Hub` only hands it to the flattening, which decodes
    /// it (`ItemBaseTrait::weapon` reads it)
    pub weapon: u128,
}

pub impl ItemBaseStorePacking of starknet::storage_access::StorePacking<ItemBase, felt252> {
    fn pack(value: ItemBase) -> felt252 {
        PackingAssert::assert_fits(value.slot.into(), P4, 'packing: slot above 4 b');
        PackingAssert::assert_fits(value.hands.into(), P4, 'packing: hands above 4 b');
        PackingTrait::join(
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
            value.weapon,
        )
    }
    fn unpack(value: felt252) -> ItemBase {
        let (low, high) = PackingTrait::split(value);
        ItemBase {
            base: LimbTrait::low_field(low, P16.try_into().unwrap()).try_into().unwrap(),
            requirement: LimbTrait::byte_at(low, P16),
            rarity: LimbTrait::byte_at(low, P24),
            level: LimbTrait::byte_at(low, P32),
            flags: LimbTrait::byte_at(low, P40),
            look: LimbTrait::u16_at(low, P48),
            set: LimbTrait::u16_at(low, P64),
            owner_kind: LimbTrait::byte_at(low, P80),
            owner: LimbTrait::u32_at(low, P88),
            slot: LimbTrait::field(low, P120, P4).try_into().unwrap(),
            hands: LimbTrait::field(low, P124, P4).try_into().unwrap(),
            weapon: high,
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
        PackingTrait::join(low, 0)
    }
    fn unpack(value: felt252) -> ItemMods {
        let (low, _) = PackingTrait::split(value);
        let mut out: Array<Modifier> = array![];
        let mut rest = low;
        for _ in 0..5_u8 {
            let (next, bits) = DivRem::div_rem(rest, P24.try_into().unwrap());
            out
                .append(
                    Modifier {
                        id: LimbTrait::low_field(bits, P16.try_into().unwrap()).try_into().unwrap(),
                        value: LimbTrait::byte_at(bits, P16),
                    },
                );
            rest = next;
        }
        ItemMods { mods: [*out[0], *out[1], *out[2], *out[3], *out[4]] }
    }
}

#[generate_trait]
pub impl ItemModsImpl of ItemModsTrait {
    /// The item as the flattening reads it (`grimworld_logic::models::worn::Worn`): its lane of
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
/// with its `ItemMods`); the distinct modifier ids they hold, in the order met; the weapon worn,
/// its requirement and whether it is personalised (`ItemBase`'s; all 0 with no weapon, WPN-01).
/// Filled one item at a time as the store reads them (`HubStoreTrait::get_equipment`), so that no
/// item is copied. Bound: 7 lanes, 5 modifiers an item.
#[derive(Drop)]
pub struct Equipment {
    pub bases: Array<(u32, ItemBase)>,
    pub worn: Array<Worn>,
    pub modifiers: Array<u16>,
    pub weapon: u128,
    pub requirement: u8,
    pub personalised: bool,
}

#[generate_trait]
pub impl EquipmentImpl of EquipmentTrait {
    #[inline(always)]
    fn new() -> Equipment {
        Equipment {
            bases: array![],
            worn: array![],
            modifiers: array![],
            weapon: 0,
            requirement: 0,
            personalised: false,
        }
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
            self.weapon = item.base.weapon;
            self.requirement = item.base.requirement;
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
        PackingAssert::assert_fits(value.remaining.into(), P48, 'packing: remaining above 48 b');
        PackingTrait::join(
            value.known.into() + value.remaining.into() * P16 + value.hints.into() * P64, 0,
        )
    }
    fn unpack(value: felt252) -> GrimoireState {
        let (low, _) = PackingTrait::split(value);
        GrimoireState {
            known: LimbTrait::low_field(low, P16.try_into().unwrap()).try_into().unwrap(),
            remaining: LimbTrait::field(low, P16, 0x1000000000000).try_into().unwrap(),
            hints: LimbTrait::field(low, P64, P64).try_into().unwrap(),
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
        PackingAssert::assert_fits(
            value.low, 0x20000000000000000000000000000000, 'packing: pairs 0-24 overflow',
        );
        PackingAssert::assert_fits(
            value.high, 0x1000000000000000000000000000000, 'packing: pairs 25-48 overflow',
        );
        PackingTrait::join(value.low, value.high)
    }
    fn unpack(value: felt252) -> Pairs {
        let (low, high) = PackingTrait::split(value);
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

    /// `amount` less (a price the caller checked is covered).
    #[inline(always)]
    fn debited(self: Gold, amount: u64) -> Gold {
        Gold { amount: self.amount - amount }
    }
}

pub impl GoldStorePacking of starknet::storage_access::StorePacking<Gold, felt252> {
    fn pack(value: Gold) -> felt252 {
        PackingTrait::join(value.amount.into(), 0)
    }
    fn unpack(value: felt252) -> Gold {
        let (low, _) = PackingTrait::split(value);
        Gold { amount: LimbTrait::low_field(low, P64.try_into().unwrap()).try_into().unwrap() }
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
        PackingTrait::join(
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
        let (low, _) = PackingTrait::split(value);
        RiftBoard {
            day: LimbTrait::low_field(low, P32.try_into().unwrap()).try_into().unwrap(),
            cleared: LimbTrait::byte_at(low, P32),
            rifts: [
                LimbTrait::u16_at(low, P40), LimbTrait::u16_at(low, P56),
                LimbTrait::u16_at(low, P72), LimbTrait::u16_at(low, P88),
                LimbTrait::u16_at(low, P104),
            ],
        }
    }
}

// The item's, the grimoire's, gold's and the Rift board's layouts (ENG-01 §3.3); the equipment
// read for `set_build`.
#[cfg(test)]
mod tests {
    use grimworld_logic::helpers::packing::LIVE;
    use grimworld_logic::models::base::{BaseRecord, BaseTrait, Weapon, WeaponTrait, slot};
    use grimworld_logic::types::combat::{damage, weapon};
    use grimworld_logic::types::content::{MODIFIER, Record};
    use starknet::storage_access::StorePacking;
    use super::super::account::PACK;
    use super::super::lanes::{StoredLanes, StoredLanesTrait};
    use super::{
        Equipment, EquipmentTrait, Gold, GoldTrait, Grimoire, GrimoireState, IDENTIFIED, Item,
        ItemBase, ItemBaseTrait, ItemMods, Modifier, PERSONALISED, PackListTrait, Pairs, RiftBoard,
        StoredItemBase, StoredItemBaseTrait,
    };

    const TWO_128: felt252 = 0x100000000000000000000000000000000;

    #[test]
    #[available_gas(l2_gas: 355415)] // ceil(1.05 × 338490 measured)
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
            weapon: 0xFFFFFFFFFFFF,
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
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    fn test_pairs_overflow_refused() {
        StorePacking::<
            Pairs, felt252,
        >::pack(Pairs { low: 0, high: 0x1000000000000000000000000000000 });
    }

    // CBT-08a, D-158: `ItemBase.slot` at bit 120 and `hands` at 124, 4 bits each, copied from the
    // `BASE` record by the constructor every creator of an item calls.
    #[test]
    #[available_gas(l2_gas: 181094)] // ceil(1.05 × 172470 measured)
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
            weapon: maul.at(9).pack(),
        };
        assert(item == expected, 'copied from the base');
        assert(item.is_two_handed(), 'two hands');
        let feet = ItemBaseTrait::new(8, @BaseTrait::new(slot::FEET, 0), 0, 0, 1, 0, 0, 0, PACK, 5);
        assert(feet.slot == slot::FEET && feet.hands == 0 && !feet.is_two_handed(), 'feet');
        let word = StorePacking::<ItemBase, felt252>::pack(item);
        assert(StorePacking::<ItemBase, felt252>::unpack(word) == item, 'round trip');
    }

    // WPN-01: `ItemBase.weapon` at bits 128-175, its base's weapon at the item's requirement
    // (design/15's axe: 9 at requirement 0, 17 at 9; 12 at 4), 8 bits a field from bit 128.
    #[test]
    fn test_item_weapon() {
        let axe = BaseTrait::weapon(1, weapon::AXE, 9, 17, 1, 1, damage::SLASHING, 3);
        let at_0 = ItemBaseTrait::new(1, @axe, 0, 0, 0, 0, 0, 0, PACK, 5);
        let expected = Weapon {
            class: weapon::AXE,
            damage: 9,
            ticks: 1,
            range: 1,
            damage_type: damage::SLASHING,
            attribute: 3,
        };
        assert(at_0.weapon() == expected, 'axe at 0');
        let at_4 = ItemBaseTrait::new(1, @axe, 4, 0, 0, 0, 0, 0, PACK, 5);
        assert(at_4.weapon() == Weapon { damage: 12, ..expected }, 'axe at 4');
        let only = ItemBase { weapon: expected.pack(), ..Default::default() };
        let high: felt252 = 2 + 9 * 0x100 + 0x10000 + 0x1000000 + 0x100000000 + 3 * 0x10000000000;
        assert(
            StorePacking::<ItemBase, felt252>::pack(only) == high * TWO_128 + LIVE,
            'weapon at bit 128',
        );
        let word = StorePacking::<ItemBase, felt252>::pack(at_4);
        assert(StorePacking::<ItemBase, felt252>::unpack(word) == at_4, 'round trip');
        // The stored word's two paths, against the packer.
        let part = *BaseRecord::pack(@axe)[0];
        let stored = StoredItemBaseTrait::new(1, part, 4, 0, PACK, 5);
        assert(StorePacking::<ItemBase, felt252>::unpack(stored.word) == at_4, 'stored: new');
        assert(stored.base() == 1, 'stored: base');
        let held = ItemBase { owner_kind: PACK, owner: 0xFFFFFFFF, ..at_4 };
        let word = StorePacking::<ItemBase, felt252>::pack(held);
        let forfeited = StoredItemBase { word }.forfeited(0xFFFFFFFF);
        assert(
            StorePacking::<ItemBase, felt252>::unpack(forfeited.word) == held.forfeited(),
            'stored: forfeited',
        );
        let chest = BaseTrait::new(slot::CHEST, 0);
        let plain = StoredItemBaseTrait::new(0xFFFF, *BaseRecord::pack(@chest)[0], 9, 3, PACK, 7);
        assert(
            StorePacking::<
                ItemBase, felt252,
            >::unpack(plain.word) == ItemBaseTrait::new(0xFFFF, @chest, 9, 3, 0, 0, 0, 0, PACK, 7),
            'stored: armor',
        );
    }

    // The pack's list: its first free lane, the entity it holds alone.
    #[test]
    fn test_pack_list() {
        let none = StoredLanes { word: 0 };
        assert(PackListTrait::free_lane(@none) == Option::Some(0), 'never written');
        let one = StoredLanesTrait::new().added(0, 41);
        assert(PackListTrait::free_lane(@one) == Option::Some(1), 'after one');
        assert(PackListTrait::alone(@one) == Option::Some(41), 'alone');
        let two = one.added(1, 42);
        assert(PackListTrait::alone(@two) == Option::None, 'two');
        let mut full = StoredLanesTrait::new();
        for lane in 0..7_u8 {
            full = full.added(lane, 0xFFFFFFFF);
        }
        assert(PackListTrait::free_lane(@full) == Option::None, 'full');
        assert(PackListTrait::alone(@none) == Option::None, 'empty');
        assert(PackListTrait::alone(@StoredLanesTrait::new()) == Option::None, 'live alone');
        let high = StoredLanesTrait::new().added(4, 41);
        assert(PackListTrait::alone(@high) == Option::None, 'lane 4');
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'packing: slot above 4 b')]
    fn test_item_slot_too_wide() {
        StorePacking::<ItemBase, felt252>::pack(ItemBase { slot: 16, ..Default::default() });
    }

    #[test]
    #[available_gas(l2_gas: 8201)] // ceil(1.05 × 7810 measured)
    #[should_panic(expected: 'packing: hands above 4 b')]
    fn test_item_hands_too_wide() {
        StorePacking::<ItemBase, felt252>::pack(ItemBase { hands: 16, ..Default::default() });
    }

    // The items worn as `set_build` reads them: lanes and bases in lane order, the distinct
    // modifiers in the order met, the weapon's personalisation.
    #[test]
    #[available_gas(l2_gas: 150829)] // ceil(1.05 × 143646 measured)
    fn test_equipment() {
        let none = Modifier { id: 0, value: 0 };
        let weapon = Item {
            base: ItemBase {
                slot: 1,
                flags: PERSONALISED,
                requirement: 3,
                weapon: Weapon { class: weapon::AXE, damage: 11, ..Default::default() }.pack(),
                ..Default::default(),
            },
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
        let Equipment {
            bases, worn, modifiers, weapon: held, requirement, personalised,
        } = equipment;
        assert(held == 2 + 11 * 0x100 && requirement == 3, 'weapon');
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
