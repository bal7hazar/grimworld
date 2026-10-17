// CBT-08a: `Hub.set_build` (design/03 *Attributes*, *The skill bar*; design/15; ENG-01 §4.3,
// §9.3, §10; D-150, D-157 A). One call stores the bar, the attributes, the belt and the
// equipment; every rule is a refusal tested at its boundary. `Registry` is the real one, written
// with the records the rules read (`SKILL`, `ITEM`); equipment is created by
// `ItemBaseTrait::new`, which copies its `BASE`'s slot and hands (D-158); what no entrypoint can
// yet produce (known skills, pack balances, equipment entities, a level, a rank, a secondary
// profession) is set with `store`. CBT-02e (D-168): `set_build` flattens the build through
// `FlattenLibrary` and stores the snapshot's words; its worst case holds the 15 modifiers design/20
// §1.2 counts.
use core::testing::get_available_gas;
use grimworld_logic::helpers::packing::{LIVE, Lanes16, Lanes32};
use grimworld_logic::interface::{IRegistryReadDispatcher, IRegistryReadDispatcherTrait};
use grimworld_logic::models::base::{Base, BaseRecord, BaseTrait};
use grimworld_logic::models::build::SnapshotBuildTrait;
use grimworld_logic::models::build::errors::{MAX_HEALTH, SOURCE_COUNT};
use grimworld_logic::models::item::{ItemRecord, ItemTrait, class};
use grimworld_logic::models::kit::{KitRecord, KitTrait};
use grimworld_logic::models::location::{LocationRecord, LocationTrait, kind as location_kind};
use grimworld_logic::models::member_kit::MemberKitTrait;
use grimworld_logic::models::member_stats::MemberStatsTrait;
use grimworld_logic::models::modifier::{ModifierRecord, ModifierTrait, slot as modifier_slot};
use grimworld_logic::models::region::{RegionRecord, RegionTrait};
use grimworld_logic::models::skill::{SkillRecord, SkillTrait};
use grimworld_logic::models::worn::Worn;
use grimworld_logic::models::worn::errors::{
    INSIGNIA_PIECE, NO_MODIFIER, SLOT_TYPE, VALUE as MODIFIER_VALUE,
};
use grimworld_logic::types::combat::{damage, skill_kind, weapon};
use grimworld_logic::types::content::{
    BASE, ITEM, KIT, LAST_KIND, LOCATION, MODIFIER, REGION, SKILL,
};
use grimworld_logic::types::passive::{Passive, PassiveTrait, id as passive_id};
use grimworld_persistent::models::account::{OwnerTrait, PACK, VAULT};
use grimworld_persistent::models::adventurer::errors::{
    ADVENTURER_DELETED, BELT_NOT_IN_PACK, COUNT_WITHOUT_ITEM, DUPLICATE_ITEM, DUPLICATE_SKILL,
    ELITE_SLOT, NOT_A_POTION, NOT_IN_HUB, NOT_OWNER, NO_ADVENTURER, NO_ATTRIBUTE, NO_SKILL,
    PACK_HOLDS_EQUIPMENT, PACK_HOLDS_GOLD, POINTS, RANK_ABOVE_12, SKILL_ALREADY_KNOWN,
    SKILL_NOT_KNOWN, SKILL_NOT_SOLD, SKILL_PRICE, SKILL_PROFESSION, TWO_ELITES, TWO_HANDS,
    WRONG_SLOT,
};
use grimworld_persistent::models::adventurer::{AdventurerCore, Build, BuildTrait, NO_ELITE};
use grimworld_persistent::models::item::errors::{A_COMPONENT, NOT_IN_PACK, UNIDENTIFIED};
use grimworld_persistent::models::item::{
    COMMON, COMPONENT, Gold, IDENTIFIED, ItemBase, ItemBaseTrait, ItemMods, ItemModsTrait, Modifier,
};
use grimworld_persistent::models::snapshot::StoredSnapshotTrait;
use grimworld_persistent::models::stored_build::errors::{
    BELT_LAYOUT, BUILD_LAYOUT, EQUIPPED_LAYOUT,
};
use grimworld_persistent::systems::hub::{
    IHubAdminDispatcher, IHubAdminDispatcherTrait, IHubDispatcher, IHubDispatcherTrait,
    IHubSafeDispatcher, IHubSafeDispatcherTrait,
};
use grimworld_persistent::systems::registry::{
    IRegistryAdminDispatcher, IRegistryAdminDispatcherTrait, Inputs,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, load, map_entry_address,
    start_cheat_caller_address, store,
};
use starknet::ContractAddress;
use starknet::storage_access::StorePacking;

const ADMIN: felt252 = 0xad;
const ALICE: felt252 = 0xa11ce;
const BOB: felt252 = 0xb0b;
const VANGUARD: u8 = 1;
const WARDEN: u8 = 2;
const ARCANIST: u8 = 3;

// Skills: 1-8 the Vanguard's, 4 elite; 9 a second Vanguard elite; 10 the Warden's; 11 the
// Arcanist's. Known: 1 to 12 (12 has no record).
const ELITE: u16 = 4;
const SECOND_ELITE: u16 = 9;
const WARDEN_SKILL: u16 = 10;
const ARCANIST_SKILL: u16 = 11;
const NO_RECORD: u16 = 12;
// Items 1 to 22: potions 1, 8, 15, 22 (lane 1 of pages 0 to 3), every other an ingredient.
const INGREDIENT: u32 = 2;
// Bases: 1 sword, 2 maul (two hands), 3 shield, 4 chest, 5 legs, 6 head, 7 hands, 8 feet.
// Entities: 101-107 a sword, a shield and five armor pieces in Alice's first pack; 108 a maul.
const MAUL: u32 = 108;
const OTHERS: u32 = 109; // a chest in Bob's pack
const IN_VAULT: u32 = 110; // a chest in Alice's vault
const A_COMPONENT_ENTITY: u32 = 111;
const FINE_CLOSED: u32 = 112; // a fine chest, unidentified
const FINE_OPEN: u32 = 113; // a fine chest, identified
const NOT_WORN: u32 = 114; // its base, 9, has no slot
const NEVER: u32 = 115; // an entity never written

fn addr(value: felt252) -> ContractAddress {
    value.try_into().unwrap()
}

#[derive(Copy, Drop)]
struct World {
    hub: ContractAddress,
    registry: ContractAddress,
}

fn skill(profession: u8, elite: bool) -> Span<felt252> {
    SkillTrait::new(profession, 1, 1, 5, 0, 1, 8, 1, 1, elite, [Default::default(); 3]).pack()
}

/// An `ITEM` of `class`; a potion heals its holder, the legal carrier the registry requires
/// (`ItemAssert::assert_legal`, D-166).
fn item(class: u8) -> Span<felt252> {
    let entry = if class == class::POTION {
        grimworld_logic::types::effect::Entry {
            kind: grimworld_logic::types::effect::kind::HEAL,
            v0: 20,
            v12: 20,
            target: grimworld_logic::types::effect::target::SELF,
            shape: grimworld_logic::types::effect::shape::SINGLE,
            filter: grimworld_logic::types::effect::filter::ALLIES,
            ..Default::default(),
        }
    } else {
        Default::default()
    };
    ItemTrait::new(class, 1, 0, 1, 0, entry, 0, 0).pack()
}

fn setup() -> World {
    let class = declare("Registry").unwrap().contract_class();
    let (registry, _) = class.deploy(@array![ADMIN]).unwrap();
    let class = declare("Hub").unwrap().contract_class();
    let (hub, _) = class.deploy(@array![ADMIN, registry.into(), 3, 4, 5]).unwrap();
    let flatten = *declare("FlattenLibrary").unwrap().contract_class().class_hash;
    start_cheat_caller_address(hub, addr(ADMIN));
    IHubAdminDispatcher { contract_address: hub }
        .set_contracts(registry, addr(3), addr(4), addr(5), flatten);

    start_cheat_caller_address(registry, addr(ADMIN));
    let admin = IRegistryAdminDispatcher { contract_address: registry };
    admin.set_record(REGION, 1, RegionTrait::new(1, 0, 1, 'Test Region').pack());
    admin
        .set_record(
            LOCATION,
            1,
            LocationTrait::new(
                location_kind::TOWN,
                1,
                1,
                1,
                3,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                false,
                0,
                0,
                Lanes16 { lanes: [0; 15] },
            )
                .pack(),
        );
    for id in 1..9_u32 {
        admin.set_record(SKILL, id, skill(VANGUARD, id == ELITE.into()));
    }
    admin.set_record(SKILL, 9, skill(VANGUARD, true));
    admin.set_record(SKILL, 10, skill(WARDEN, false));
    admin.set_record(SKILL, 11, skill(ARCANIST, false));
    for id in 1..23_u32 {
        let kind = if id % 7 == 1 {
            class::POTION
        } else {
            class::INGREDIENT
        };
        admin.set_record(ITEM, id, item(kind));
    }
    World { hub, registry }
}

fn act(world: World, who: felt252) -> IHubDispatcher {
    start_cheat_caller_address(world.hub, addr(who));
    IHubDispatcher { contract_address: world.hub }
}

fn try_act(world: World, who: felt252) -> IHubSafeDispatcher {
    start_cheat_caller_address(world.hub, addr(who));
    IHubSafeDispatcher { contract_address: world.hub }
}

fn refused<T, +Drop<T>>(result: Result<T, Array<felt252>>, message: felt252) {
    match result {
        Result::Ok(_) => core::panic_with_felt252('should be refused'),
        Result::Err(data) => assert(*data.at(0) == message, *data.at(0)),
    }
}

fn accepted<T, +Drop<T>>(result: Result<T, Array<felt252>>) {
    match result {
        Result::Ok(_) => {},
        Result::Err(data) => core::panic_with_felt252(*data.at(0)),
    }
}

// Storage keys (ENG-01 §3.3).
fn adventurer_word(id: u32, word: felt252) -> felt252 {
    map_entry_address(selector!("adventurers"), array![id.into()].span()) + word
}
fn read(target: ContractAddress, key: felt252) -> felt252 {
    *load(target, key, 1).at(0)
}
fn write(target: ContractAddress, key: felt252, value: felt252) {
    store(target, key, array![value].span());
}

fn core_of(world: World, id: u32) -> AdventurerCore {
    StorePacking::unpack(read(world.hub, adventurer_word(id, 0)))
}
/// Level, guild rank and secondary profession, as a later lot will set them.
fn set_profile(world: World, id: u32, level: u8, rank: u8, secondary: u8) {
    let core = core_of(world, id);
    write(
        world.hub,
        adventurer_word(id, 0),
        StorePacking::pack(AdventurerCore { level, rank, secondary, ..core }),
    );
}
/// Skills 1 to 12 known on page 0, as fixtures (`buy_skill`'s own tests buy theirs).
fn know_skills(world: World, id: u32) {
    let key = map_entry_address(selector!("known_skills"), array![id.into(), 0].span());
    write(world.hub, key, 0x1ffe + LIVE);
}
/// `amount` of `item` in the pack of `id`, the page's other lanes kept.
fn give(world: World, id: u32, item: u32, amount: u32) {
    let key = map_entry_address(
        selector!("balances"), array![OwnerTrait::key(PACK, id), (item / 7).into()].span(),
    );
    let stored = read(world.hub, key);
    let old: Lanes32 = if stored == 0 {
        Lanes32 { lanes: [0; 7] }
    } else {
        StorePacking::unpack(stored)
    };
    let mut lanes = array![];
    for lane in 0..7_u32 {
        lanes.append(if lane == item % 7 {
            amount
        } else {
            *old.lanes.span()[lane]
        });
    }
    let page = Lanes32 {
        lanes: [*lanes[0], *lanes[1], *lanes[2], *lanes[3], *lanes[4], *lanes[5], *lanes[6]],
    };
    write(world.hub, key, StorePacking::pack(page));
}
/// The `BASE` records of the bases above; 9 has no slot.
fn base_record(base: u16) -> Base {
    match base {
        1 => BaseTrait::new(1, 1),
        2 => BaseTrait::new(1, 2),
        9 => BaseTrait::new(0, 0),
        _ => BaseTrait::new((base - 1).try_into().unwrap(), 0),
    }
}
/// An entity as its creator writes it (`ItemBaseTrait::new`: the base's slot and hands copied).
fn put_item(world: World, entity: u32, base: u16, rarity: u8, flags: u8, kind: u8, owner: u32) {
    let key = map_entry_address(selector!("items"), array![entity.into()].span());
    let item = ItemBaseTrait::new(base, @base_record(base), 0, rarity, 0, flags, 0, 0, kind, owner);
    write(world.hub, key, StorePacking::pack(item));
}

/// The `MODIFIER` records of the flattening's tests (design/19 §4, within design/20's per-source
/// bounds): 1–3 a prefix, a suffix and an inscription (life steal 1…5 on a hit, costing 7 armor
/// against cold); 4–5 a suffix and an inscription likewise; 6–10 insignias made for the chest,
/// the legs, the head, the hands and the feet, 11–15 runes (armor against fire 1…7, costing 7
/// against cold); 16 a rune costing 75 health (DS-2's floor); 17 an insignia made for the chest.
fn modifiers(world: World) {
    start_cheat_caller_address(world.registry, addr(ADMIN));
    let admin = IRegistryAdminDispatcher { contract_address: world.registry };
    let cold = PassiveTrait::new(passive_id::ARMOR_VS, damage::COLD, 0, 0, 7, 7);
    let steal = PassiveTrait::new(passive_id::LIFE_STEAL_ON_HIT, 0, 0, 0, 1, 5);
    let fire = PassiveTrait::new(passive_id::ARMOR_VS, damage::FIRE, 0, 0, 1, 7);
    let held = [
        modifier_slot::PREFIX, modifier_slot::SUFFIX, modifier_slot::INSCRIPTION,
        modifier_slot::SUFFIX, modifier_slot::INSCRIPTION,
    ];
    let mut id: u32 = 1;
    for slot in held.span() {
        admin.set_record(MODIFIER, id, ModifierTrait::new(*slot, steal, cold).pack());
        id += 1;
    }
    for piece in 3..8_u8 {
        admin.set_record(MODIFIER, id, ModifierTrait::insignia(piece, fire, cold).pack());
        id += 1;
    }
    for _ in 0..5_u8 {
        admin.set_record(MODIFIER, id, ModifierTrait::new(modifier_slot::RUNE, fire, cold).pack());
        id += 1;
    }
    let health: Passive = PassiveTrait::new(passive_id::MAX_HEALTH, 0, 0, 0, -75, -75);
    admin.set_record(MODIFIER, 16, ModifierTrait::new(modifier_slot::RUNE, fire, health).pack());
    admin.set_record(MODIFIER, 17, ModifierTrait::insignia(3, fire, cold).pack());
}

/// The `ItemMods` of `entity`, as identification and the enchanter write it: each slot's
/// `(modifier, value)`, in the order prefix, suffix, inscription, insignia, rune.
fn put_mods(world: World, entity: u32, mods: [(u16, u8); 5]) {
    let key = map_entry_address(selector!("items"), array![entity.into()].span()) + 1;
    let [(a, x), (b, y), (c, z), (d, v), (e, w)] = mods;
    let lanes = [
        Modifier { id: a, value: x }, Modifier { id: b, value: y }, Modifier { id: c, value: z },
        Modifier { id: d, value: v }, Modifier { id: e, value: w },
    ];
    write(world.hub, key, StorePacking::pack(ItemMods { mods: lanes }));
}

/// Items 101–107 made fine and identified, so that they hold modifiers (design/15: a common item
/// has none).
fn fine_items(world: World, id: u32) {
    for i in 0..7_u32 {
        let base: u16 = if i == 0 {
            1
        } else {
            (i + 2).try_into().unwrap()
        };
        put_item(world, 101 + i, base, 1, IDENTIFIED, PACK, id);
    }
}

/// The widest equipment design/20 §1.2 counts: the sword's prefix, suffix and inscription, the
/// shield's suffix and inscription, each piece's insignia and rune: 15 modifiers, 30 passives.
fn widest_equipment(world: World, id: u32) {
    modifiers(world);
    fine_items(world, id);
    put_mods(world, 101, [(1, 5), (2, 5), (3, 5), (0, 0), (0, 0)]);
    put_mods(world, 102, [(0, 0), (4, 5), (5, 5), (0, 0), (0, 0)]);
    let mut k: u16 = 0;
    while k < 5 {
        put_mods(world, 103 + k.into(), [(0, 0), (0, 0), (0, 0), (6 + k, 7), (11 + k, 7)]);
        k += 1;
    }
}

/// The snapshot's three words as `set_build` stored them for `id`: `(stats, bar, kit)`, the kit
/// word as stored (its content version and `LIVE` in it).
fn stored_snapshot(world: World, id: u32) -> (felt252, felt252, felt252) {
    let key = map_entry_address(selector!("snapshots"), array![id.into()].span());
    (read(world.hub, key), read(world.hub, key + 1), read(world.hub, key + 2))
}

/// What the flattening makes of the build `set_build` stored for `id` (its profession, not
/// personalised, the belt given), computed here from the same records: `SnapshotBuildTrait::words`
/// on the items 101–107 as they are worn, and the records of the modifiers `ids` read from the
/// registry. The kit word sealed with the registry's content version, as `set_build` stores it.
fn flattened(
    world: World, id: u32, level: u8, ids: Span<u16>, belt_items: [u32; 4], counts: [u8; 4],
) -> (felt252, felt252, felt252) {
    let build: Build = StorePacking::unpack(read(world.hub, adventurer_word(id, 2)));
    let registry = IRegistryReadDispatcher { contract_address: world.registry };
    let (_, _, skill_parts) = registry.bundle(build.request().span());
    let key = map_entry_address(selector!("items"), array![101].span());
    let weapon: ItemBase = StorePacking::unpack(read(world.hub, key));
    let loadout = build
        .loadout(
            level,
            core_of(world, id).profession,
            build.bar_kinds(skill_parts),
            weapon.weapon(),
            weapon.requirement,
            false,
            belt_items,
            counts,
        );
    let mut worn: Array<Worn> = array![];
    for lane in 0..7_u8 {
        let key = map_entry_address(selector!("items"), array![(101 + lane.into())].span()) + 1;
        let mods: ItemMods = StorePacking::unpack(read(world.hub, key));
        let slot = if lane == 0 {
            1
        } else {
            lane + 1
        };
        worn.append(mods.worn(lane, slot));
    }
    let mut requests = array![];
    for modifier in ids {
        requests.append((MODIFIER, (*modifier).into()));
    }
    let (_, _, parts) = registry.bundle(requests.span());
    let (stats, bar, kit) = SnapshotBuildTrait::words(@loadout, worn.span(), ids, parts);
    (stats, bar, StoredSnapshotTrait::seal(kit, epoch(world)))
}

/// The flattening epoch a snapshot stored now is sealed with (D-169): the registry's inputs
/// version and `Hub`'s rules epoch.
fn epoch(world: World) -> u64 {
    let registry = IRegistryReadDispatcher { contract_address: world.registry };
    let (_, inputs, _) = registry.bundle(array![].span());
    let rules: u16 = read(world.hub, selector!("rules_epoch")).try_into().unwrap();
    StoredSnapshotTrait::epoch(inputs, rules)
}

/// Alice's account and one adventurer of `profession`: adventurer 1; Bob's Vanguard: 2. Alice
/// knows skills 1 to 12, holds 3 of each potion, and has the entities above.
fn adventurer(world: World, profession: u8) -> u32 {
    let hub = act(world, ALICE);
    hub.register();
    let id = hub.create_adventurer('Aldric', profession);
    let bob = act(world, BOB);
    bob.register();
    bob.create_adventurer('Brenna', VANGUARD);
    know_skills(world, id);
    for potion in array![1_u32, 8, 15, 22] {
        give(world, id, potion, 3);
    }
    give(world, id, INGREDIENT, 3);
    for i in 0..7_u32 {
        let base: u16 = if i == 0 {
            1
        } else {
            (i + 2).try_into().unwrap()
        };
        put_item(world, 101 + i, base, 0, 0, PACK, id);
    }
    put_item(world, MAUL, 2, 0, 0, PACK, id);
    put_item(world, OTHERS, 4, 0, 0, PACK, 2);
    put_item(world, IN_VAULT, 4, 0, 0, VAULT, 1);
    put_item(world, A_COMPONENT_ENTITY, 4, 0, COMPONENT, PACK, id);
    put_item(world, FINE_CLOSED, 4, 1, 0, PACK, id);
    put_item(world, FINE_OPEN, 4, 1, IDENTIFIED, PACK, id);
    put_item(world, NOT_WORN, 9, 0, 0, PACK, id);
    id
}

// The words `set_build` takes (ENG-01 §3.3), without `LIVE`.
const P128: felt252 = 0x100000000000000000000000000000000;
fn build(bar: [u16; 8], ranks: [u8; 9], elite: u8) -> felt252 {
    let mut low: felt252 = 0;
    let mut factor: felt252 = 1;
    for skill in bar.span() {
        low += (*skill).into() * factor;
        factor *= 0x10000;
    }
    let mut high: felt252 = 0;
    factor = 1;
    for rank in ranks.span() {
        high += (*rank).into() * factor;
        factor *= 0x10;
    }
    low + (high + elite.into() * 0x10000000000) * P128
}
fn bar(skills: [u16; 8]) -> felt252 {
    build(skills, [0; 9], NO_ELITE)
}
fn ranks(values: [u8; 9]) -> felt252 {
    build([0; 8], values, NO_ELITE)
}
fn belt(items: [u32; 4], counts: [u8; 4]) -> felt252 {
    let [a, b, c, d] = items;
    let [w, x, y, z] = counts;
    let lane4: u32 = w.into() + x.into() * 0x100 + y.into() * 0x10000 + z.into() * 0x1000000;
    StorePacking::pack(Lanes32 { lanes: [a, b, c, d, lane4, 0, 0] }) - LIVE
}
fn equipped(entities: [u32; 7]) -> felt252 {
    StorePacking::pack(Lanes32 { lanes: entities }) - LIVE
}
/// No skill, no rank, no elite (`elite_slot` 255).
fn empty() -> felt252 {
    bar([0; 8])
}
/// The chest's lane alone.
fn chest(entity: u32) -> felt252 {
    equipped([0, 0, entity, 0, 0, 0, 0])
}

fn set(world: World, id: u32, build: felt252, belt: felt252, equipped: felt252) {
    act(world, ALICE).set_build(id, build, belt, equipped);
}
fn try_set(
    world: World, id: u32, build: felt252, belt: felt252, equipped: felt252,
) -> Result<(), Array<felt252>> {
    #[feature("safe_dispatcher")]
    let result = try_act(world, ALICE).set_build(id, build, belt, equipped);
    result
}

// ---- the worst case, stored as sent
// --------------------------------------------------------------

/// The budget of the `set_build` call alone in its worst case (D-158 (c), D-168: a hub action's
/// target is its measure): ceil(1.05 × 8,097,073 measured), snforge, `get_available_gas` around
/// the dispatcher call. snforge prices a new slot as an overwrite: the first write's premium is
/// the node probe's (`contracts/tools/lifecycle_probe.py`). Raised from 3,108,768 (2,960,731
/// measured, no modifier worn): the flattening of the 15 modifiers, D-160, D-168. Raised again to
/// ceil(1.05 × 8,667,373 measured) on Scarb 2.20.1 (FND-11, D-180): the compiler moved the cost.
/// Raised again to ceil(1.05 × 9,190,003 measured) by WPN-01 (D-310): the build's checks in a
/// second `FlattenLibrary` call (+136,410, the coordinator's option A) and the loadout's weapon
/// and bar kinds (8,753,783 measured after the move out of Hub, before the mechanism).
const WORST_CASE_CALL: u128 = 9649504;

// The worst case of ENG-01 §9.3 and §10: 8 skills (an elite in slot 3), every attribute point of
// a level 20 Copper spent (12/12/3: 97 + 97 + 6 = 200), four potions on four pack pages, seven
// pieces worn holding the 15 modifiers design/20 §1.2 counts, flattened by `FlattenLibrary`
// (D-168). Writes: `build`, `belt`, `equipped`, overwritten, each the word sent plus `LIVE`; the
// snapshot's three words, new at the adventurer's first `set_build`, then overwritten (the second
// call). The words stored are the flattening's (AC-1).
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 126814185)] // ceil(1.05 × 120775414 measured)
fn test_set_build_worst_case() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    set_profile(world, id, 20, 2, 0);
    widest_equipment(world, id);
    let words = (
        build([1, 2, 3, ELITE, 5, 6, 7, 8], [12, 12, 3, 0, 0, 0, 0, 0, 0], 3),
        belt([1, 8, 15, 22], [3, 3, 3, 3]),
        equipped([101, 102, 103, 104, 105, 106, 107]),
    );
    let (b, l, e) = words;
    let before = array![
        read(world.hub, adventurer_word(id, 2)), read(world.hub, adventurer_word(id, 3)),
        read(world.hub, adventurer_word(id, 4)),
    ];
    let others = array![
        read(world.hub, adventurer_word(id, 0)), read(world.hub, adventurer_word(id, 1)),
        read(world.hub, adventurer_word(id, 5)),
    ];
    assert(stored_snapshot(world, id) == (0, 0, 0), 'no snapshot yet');
    let hub = act(world, ALICE);
    let gas = get_available_gas();
    hub.set_build(id, b, l, e);
    let call = gas - get_available_gas();
    println!("gas set_build, worst case, first (snapshot new): {}", call);
    // D-158: the call alone carries its own budget, beside the test's (deploy and setup included).
    assert(call <= WORST_CASE_CALL, 'set_build over its budget');
    let ids = array![1_u16, 2, 3, 4, 5, 6, 11, 7, 12, 8, 13, 9, 14, 10, 15].span();
    let expected = flattened(world, id, 20, ids, [1, 8, 15, 22], [3, 3, 3, 3]);
    assert(stored_snapshot(world, id) == expected, 'the flattening stored');
    let gas = get_available_gas();
    hub.set_build(id, b, l, e);
    println!(
        "gas set_build, worst case, again (snapshot overwritten): {}", gas - get_available_gas(),
    );
    assert(stored_snapshot(world, id) == expected, 'the same words');
    let after = array![
        read(world.hub, adventurer_word(id, 2)), read(world.hub, adventurer_word(id, 3)),
        read(world.hub, adventurer_word(id, 4)),
    ];
    assert(*before[0] != 0 && *before[1] != 0 && *before[2] != 0, 'overwritten, not new');
    assert(*after[0] == b + LIVE && *after[1] == l + LIVE && *after[2] == e + LIVE, 'stored');
    // Nothing else of the adventurer changed.
    let unchanged = array![
        read(world.hub, adventurer_word(id, 0)), read(world.hub, adventurer_word(id, 1)),
        read(world.hub, adventurer_word(id, 5)),
    ];
    assert(others == unchanged, 'core, place, name kept');
}

// The worst case's make-up: each part alone, the others empty (the report's cost table).
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 91234853)] // ceil(1.05 × 86890336 measured)
fn test_set_build_parts() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    set_profile(world, id, 20, 2, 0);
    let hub = act(world, ALICE);
    let gas = get_available_gas();
    hub.set_build(id, build([1, 2, 3, ELITE, 5, 6, 7, 8], [0; 9], 3), 0, 0);
    println!("gas set_build, 8 skills alone: {}", gas - get_available_gas());
    let gas = get_available_gas();
    hub.set_build(id, ranks([12, 12, 3, 0, 0, 0, 0, 0, 0]), 0, 0);
    println!("gas set_build, 200 points alone: {}", gas - get_available_gas());
    let gas = get_available_gas();
    hub.set_build(id, empty(), belt([1, 8, 15, 22], [3, 3, 3, 3]), 0);
    println!("gas set_build, 4 potions on 4 pages alone: {}", gas - get_available_gas());
    let gas = get_available_gas();
    hub.set_build(id, empty(), 0, equipped([101, 102, 103, 104, 105, 106, 107]));
    println!("gas set_build, 7 pieces alone: {}", gas - get_available_gas());
}

// An empty build: one registry call (the content version, D-168), no record; the words of a new
// adventurer back, and the snapshot of a level 20 Vanguard without equipment.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 86908994)] // ceil(1.05 × 82770470 measured)
fn test_set_build_empty() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    set_profile(world, id, 20, 2, 0);
    set(
        world,
        id,
        build([1, 2, 3, ELITE, 5, 6, 7, 8], [12, 12, 3, 0, 0, 0, 0, 0, 0], 3),
        belt([1, 8, 15, 22], [3, 3, 3, 3]),
        equipped([101, 102, 103, 104, 105, 106, 107]),
    );
    let hub = act(world, ALICE);
    let gas = get_available_gas();
    hub.set_build(id, empty(), 0, 0);
    println!("gas set_build, empty: {}", gas - get_available_gas());
    assert(read(world.hub, adventurer_word(id, 2)) == empty() + LIVE, 'build');
    assert(read(world.hub, adventurer_word(id, 3)) == LIVE, 'belt');
    assert(read(world.hub, adventurer_word(id, 4)) == LIVE, 'equipped');
    let (stats, _, kit) = stored_snapshot(world, id);
    assert(MemberStatsTrait::unpack(stats).max_health == 480, 'level 20 health');
    assert(
        MemberKitTrait::unpack(StoredSnapshotTrait::kit(kit, epoch(world))).belt == [0; 4],
        'no belt',
    );
}

// ---- who, where, and the layouts
// -----------------------------------------------------------------

#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 83537563)] // ceil(1.05 × 79559583 measured)
fn test_set_build_ownership_refusals() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    refused(try_set(world, 9, empty(), 0, 0), NO_ADVENTURER);
    #[feature("safe_dispatcher")]
    refused(try_act(world, BOB).set_build(id, empty(), 0, 0), NOT_OWNER);
    // Inside an instance: the build is locked (design/03).
    let place = read(world.hub, adventurer_word(id, 1));
    write(world.hub, adventurer_word(id, 1), place + 0x1000000000000000000000000);
    refused(try_set(world, id, empty(), 0, 0), NOT_IN_HUB);
    write(world.hub, adventurer_word(id, 1), place);
    accepted(try_set(world, id, empty(), 0, 0));
    // Deleted.
    let core = core_of(world, id);
    write(
        world.hub, adventurer_word(id, 0), StorePacking::pack(AdventurerCore { status: 1, ..core }),
    );
    refused(try_set(world, id, empty(), 0, 0), ADVENTURER_DELETED);
}

// A bit outside the fields: 164-167 and 176 up in `build`, 160 up in `belt`, 224 up in
// `equipped`; bit 250 (`LIVE`) is not the caller's to send.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 86484524)] // ceil(1.05 × 82366213 measured)
fn test_set_build_layout_refusals() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    let bit163 = 0x800000000 * P128;
    let bit164 = 0x1000000000 * P128;
    let bit167 = 0x8000000000 * P128;
    let bit176 = 0x1000000000000 * P128;
    let bit250 = LIVE;
    accepted(try_set(world, id, empty(), 0, 0));
    refused(try_set(world, id, empty() + bit164, 0, 0), BUILD_LAYOUT);
    refused(try_set(world, id, empty() + bit167, 0, 0), BUILD_LAYOUT);
    refused(try_set(world, id, empty() + bit176, 0, 0), BUILD_LAYOUT);
    refused(try_set(world, id, empty() + bit250, 0, 0), BUILD_LAYOUT);
    // Bit 163 is the last attribute field's: a rank, refused by its own rule.
    refused(try_set(world, id, empty() + bit163, 0, 0), NO_ATTRIBUTE);
    let bit159 = 0x80000000 * P128;
    let bit160 = 0x100000000 * P128;
    refused(try_set(world, id, empty(), bit160, 0), BELT_LAYOUT);
    refused(try_set(world, id, empty(), bit250, 0), BELT_LAYOUT);
    // Bit 159 is slot 3's count: a count without an item.
    refused(try_set(world, id, empty(), bit159, 0), COUNT_WITHOUT_ITEM);
    let bit224 = 0x1000000000000000000000000 * P128;
    refused(try_set(world, id, empty(), 0, bit224), EQUIPPED_LAYOUT);
    refused(try_set(world, id, empty(), 0, bit250), EQUIPPED_LAYOUT);
}

// ---- the bar
// -------------------------------------------------------------------------------------

#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 83075174)] // ceil(1.05 × 79119213 measured)
fn test_bar_duplicate_refused() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    accepted(try_set(world, id, bar([1, 2, 3, 5, 6, 7, 8, 0]), 0, 0));
    refused(try_set(world, id, bar([1, 2, 3, 5, 6, 7, 8, 1]), 0, 0), DUPLICATE_SKILL);
    refused(try_set(world, id, bar([0, 2, 0, 0, 0, 0, 0, 2]), 0, 0), DUPLICATE_SKILL);
}

// Known: skills 1 to 12 on page 0; skill 13 is in no bit. 12 is known but has no record.
#[test]
// gas: raised, WPN-01: set_build's second FlattenLibrary call and the bar's kinds read (D-310)
#[available_gas(l2_gas: 92608462)] // ceil(1.05 × 88198535 measured)
fn test_bar_known_and_registered() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    refused(try_set(world, id, bar([13, 0, 0, 0, 0, 0, 0, 0]), 0, 0), SKILL_NOT_KNOWN);
    // A skill past page 255 cannot be known.
    refused(try_set(world, id, bar([0, 0, 0, 0, 0, 0, 0, 65000]), 0, 0), SKILL_NOT_KNOWN);
    refused(try_set(world, id, bar([NO_RECORD, 0, 0, 0, 0, 0, 0, 0]), 0, 0), NO_SKILL);
    // Forgotten: the same skill once its bit is cleared.
    accepted(try_set(world, id, bar([8, 0, 0, 0, 0, 0, 0, 0]), 0, 0));
    let key = map_entry_address(selector!("known_skills"), array![id.into(), 0].span());
    write(world.hub, key, 0xfe + LIVE);
    refused(try_set(world, id, bar([8, 0, 0, 0, 0, 0, 0, 0]), 0, 0), SKILL_NOT_KNOWN);
    accepted(try_set(world, id, bar([7, 0, 0, 0, 0, 0, 0, 0]), 0, 0));
}

// Of the primary or the secondary profession (design/03).
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 83954917)] // ceil(1.05 × 79957063 measured)
fn test_bar_profession() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    refused(try_set(world, id, bar([1, WARDEN_SKILL, 0, 0, 0, 0, 0, 0]), 0, 0), SKILL_PROFESSION);
    set_profile(world, id, 1, 2, WARDEN);
    accepted(try_set(world, id, bar([1, WARDEN_SKILL, 0, 0, 0, 0, 0, 0]), 0, 0));
    refused(
        try_set(world, id, bar([1, WARDEN_SKILL, ARCANIST_SKILL, 0, 0, 0, 0, 0]), 0, 0),
        SKILL_PROFESSION,
    );
}

// At most one elite; `elite_slot` names it, or is 255 without one.
#[test]
// gas: raised, WPN-01: set_build's second FlattenLibrary call and the bar's kinds read (D-310)
#[available_gas(l2_gas: 93643450)] // ceil(1.05 × 89184238 measured)
fn test_bar_elite() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    accepted(try_set(world, id, build([1, 0, 0, 0, 0, 0, 0, ELITE], [0; 9], 7), 0, 0));
    refused(try_set(world, id, build([1, 0, 0, 0, 0, 0, 0, ELITE], [0; 9], 6), 0, 0), ELITE_SLOT);
    refused(
        try_set(world, id, build([1, 0, 0, 0, 0, 0, 0, ELITE], [0; 9], NO_ELITE), 0, 0), ELITE_SLOT,
    );
    refused(try_set(world, id, build([1, 0, 0, 0, 0, 0, 0, 0], [0; 9], 0), 0, 0), ELITE_SLOT);
    refused(try_set(world, id, build([0; 8], [0; 9], 0), 0, 0), ELITE_SLOT);
    refused(
        try_set(world, id, build([ELITE, 0, 0, 0, 0, 0, 0, SECOND_ELITE], [0; 9], 0), 0, 0),
        TWO_ELITES,
    );
}

// ---- the attributes
// ------------------------------------------------------------------------------

// Ranks 0 to 12 (design/03); a level 20 Copper has 200 points.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 86932982)] // ceil(1.05 × 82793316 measured)
fn test_attributes_rank_and_points() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    set_profile(world, id, 20, 2, 0);
    accepted(try_set(world, id, ranks([12, 12, 3, 0, 0, 0, 0, 0, 0]), 0, 0));
    refused(try_set(world, id, ranks([12, 12, 3, 1, 0, 0, 0, 0, 0]), 0, 0), POINTS);
    refused(try_set(world, id, ranks([13, 0, 0, 0, 0, 0, 0, 0, 0]), 0, 0), RANK_ABOVE_12);
    refused(try_set(world, id, ranks([0, 0, 0, 0, 15, 0, 0, 0, 0]), 0, 0), RANK_ABOVE_12);
    // Tin gives 15 more, Copper 15 more; above level 20 nothing more.
    set_profile(world, id, 20, 1, 0);
    refused(try_set(world, id, ranks([12, 12, 3, 0, 0, 0, 0, 0, 0]), 0, 0), POINTS);
    accepted(try_set(world, id, ranks([12, 11, 3, 0, 0, 0, 0, 0, 0]), 0, 0)); // 180 of 185
    refused(try_set(world, id, ranks([12, 12, 0, 0, 0, 0, 0, 0, 0]), 0, 0), POINTS); // 194
}

// A level 1 Wood has no point; a level 1 Tin has 15 (design/03); each level band's step.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 103175388)] // ceil(1.05 × 98262274 measured)
fn test_attributes_points_by_level() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    accepted(try_set(world, id, ranks([0; 9]), 0, 0));
    refused(try_set(world, id, ranks([1, 0, 0, 0, 0, 0, 0, 0, 0]), 0, 0), POINTS);
    set_profile(world, id, 1, 1, 0);
    accepted(try_set(world, id, ranks([5, 0, 0, 0, 0, 0, 0, 0, 0]), 0, 0));
    refused(try_set(world, id, ranks([5, 1, 0, 0, 0, 0, 0, 0, 0]), 0, 0), POINTS);
    // Level 10: 45 points (9 levels of 5); level 11: 55; level 16: 110.
    set_profile(world, id, 10, 0, 0);
    accepted(try_set(world, id, ranks([8, 0, 0, 0, 0, 0, 0, 0, 0]), 0, 0)); // 37
    refused(try_set(world, id, ranks([9, 0, 0, 0, 0, 0, 0, 0, 0]), 0, 0), POINTS); // 48
    accepted(try_set(world, id, ranks([8, 3, 0, 0, 0, 0, 0, 0, 0]), 0, 0)); // 37 + 6 = 43
    accepted(try_set(world, id, ranks([8, 3, 1, 1, 0, 0, 0, 0, 0]), 0, 0)); // 45
    refused(try_set(world, id, ranks([8, 3, 1, 1, 1, 0, 0, 0, 0]), 0, 0), POINTS); // 46
    set_profile(world, id, 11, 0, 0);
    accepted(try_set(world, id, ranks([8, 3, 1, 1, 4, 0, 0, 0, 0]), 0, 0)); // 55
    refused(try_set(world, id, ranks([8, 3, 1, 2, 4, 0, 0, 0, 0]), 0, 0), POINTS); // 56
    set_profile(world, id, 16, 0, 0);
    accepted(try_set(world, id, ranks([12, 4, 1, 1, 1, 0, 0, 0, 0]), 0, 0)); // 110
    refused(try_set(world, id, ranks([12, 4, 2, 1, 0, 0, 0, 0, 0]), 0, 0), POINTS); // 111
    set_profile(world, id, 99, 2, 0);
    accepted(try_set(world, id, ranks([12, 12, 3, 0, 0, 0, 0, 0, 0]), 0, 0));
    refused(try_set(world, id, ranks([12, 12, 3, 1, 0, 0, 0, 0, 0]), 0, 0), POINTS);
}

// The build-local indices (D-157 A): 0-4 the primary's, 5-8 the secondary's without its primary
// attribute. A Warden has 4 attributes, a Vanguard and an Arcanist 5.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 94087318)] // ceil(1.05 × 89606969 measured)
fn test_attributes_indices() {
    let world = setup();
    let id = adventurer(world, WARDEN);
    set_profile(world, id, 20, 2, 0);
    accepted(try_set(world, id, ranks([1, 1, 1, 1, 0, 0, 0, 0, 0]), 0, 0));
    refused(try_set(world, id, ranks([0, 0, 0, 0, 1, 0, 0, 0, 0]), 0, 0), NO_ATTRIBUTE);
    refused(try_set(world, id, ranks([0, 0, 0, 0, 0, 1, 0, 0, 0]), 0, 0), NO_ATTRIBUTE);
    // A Vanguard secondary: its 4 attributes but Might, at 5-8.
    set_profile(world, id, 20, 2, VANGUARD);
    accepted(try_set(world, id, ranks([1, 1, 1, 1, 0, 1, 1, 1, 1]), 0, 0));
    refused(try_set(world, id, ranks([0, 0, 0, 0, 1, 0, 0, 0, 0]), 0, 0), NO_ATTRIBUTE);
    // A Warden primary with a Warden secondary is not a case (design/03); an Arcanist secondary
    // has 4 attributes but Wellspring, a Warden secondary 3.
    let other = act(world, ALICE).create_adventurer('Cedric', ARCANIST);
    know_skills(world, other);
    set_profile(world, other, 20, 2, WARDEN);
    accepted(try_set(world, other, ranks([1, 1, 1, 1, 1, 1, 1, 1, 0]), 0, 0));
    refused(try_set(world, other, ranks([0, 0, 0, 0, 0, 0, 0, 0, 1]), 0, 0), NO_ATTRIBUTE);
}

// ---- the belt
// ------------------------------------------------------------------------------------

#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 85292029)] // ceil(1.05 × 81230503 measured)
fn test_belt_items() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    refused(try_set(world, id, empty(), belt([0, 0, 0, 0], [0, 1, 0, 0]), 0), COUNT_WITHOUT_ITEM);
    // An ingredient held in the pack is not a potion; nor is an item with no record.
    refused(
        try_set(world, id, empty(), belt([INGREDIENT, 0, 0, 0], [1, 0, 0, 0]), 0), NOT_A_POTION,
    );
    refused(
        try_set(world, id, empty(), belt([INGREDIENT, 0, 0, 0], [0, 0, 0, 0]), 0), NOT_A_POTION,
    );
    refused(try_set(world, id, empty(), belt([40, 0, 0, 0], [0, 0, 0, 0]), 0), NOT_A_POTION);
    // A potion named without a count carries none, and is accepted.
    accepted(try_set(world, id, empty(), belt([0, 8, 0, 0], [0, 0, 0, 0]), 0));
}

// The pack holds 3 of each potion: the counts are within it, two slots of one item summed.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 86784071)] // ceil(1.05 × 82651496 measured)
fn test_belt_counts_within_the_pack() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    accepted(try_set(world, id, empty(), belt([1, 0, 0, 0], [3, 0, 0, 0]), 0));
    refused(try_set(world, id, empty(), belt([1, 0, 0, 0], [4, 0, 0, 0]), 0), BELT_NOT_IN_PACK);
    accepted(try_set(world, id, empty(), belt([8, 0, 8, 0], [1, 0, 2, 0]), 0));
    refused(try_set(world, id, empty(), belt([8, 0, 8, 0], [2, 0, 2, 0]), 0), BELT_NOT_IN_PACK);
    // Another adventurer's potions are not in this pack.
    give(world, 2, 29, 5);
    refused(try_set(world, id, empty(), belt([29, 0, 0, 0], [1, 0, 0, 0]), 0), BELT_NOT_IN_PACK);
}

// ---- the equipment
// -------------------------------------------------------------------------------

#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 91837830)] // ceil(1.05 × 87464600 measured)
fn test_equipment_owned_and_wearable() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    accepted(try_set(world, id, empty(), 0, chest(103)));
    refused(try_set(world, id, empty(), 0, chest(OTHERS)), NOT_IN_PACK);
    refused(try_set(world, id, empty(), 0, chest(IN_VAULT)), NOT_IN_PACK);
    refused(try_set(world, id, empty(), 0, chest(NEVER)), NOT_IN_PACK);
    refused(try_set(world, id, empty(), 0, chest(A_COMPONENT_ENTITY)), A_COMPONENT);
    refused(try_set(world, id, empty(), 0, chest(FINE_CLOSED)), UNIDENTIFIED);
    accepted(try_set(world, id, empty(), 0, chest(FINE_OPEN)));
    refused(try_set(world, id, empty(), 0, chest(NOT_WORN)), WRONG_SLOT);
    refused(try_set(world, id, empty(), 0, equipped([0, 0, 103, 0, 0, 0, 103])), DUPLICATE_ITEM);
}

// Each base in its own slot; a weapon in both hands leaves the off-hand empty (design/15).
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 91513830)] // ceil(1.05 × 87156028 measured)
fn test_equipment_slots_and_hands() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    // The chest (103) in the legs' lane, the shield (102) in the weapon's.
    refused(try_set(world, id, empty(), 0, equipped([0, 0, 0, 103, 0, 0, 0])), WRONG_SLOT);
    refused(try_set(world, id, empty(), 0, equipped([102, 0, 0, 0, 0, 0, 0])), WRONG_SLOT);
    refused(try_set(world, id, empty(), 0, equipped([0, 0, 0, 0, 0, 0, 101])), WRONG_SLOT);
    accepted(try_set(world, id, empty(), 0, equipped([101, 102, 0, 0, 0, 0, 0])));
    accepted(try_set(world, id, empty(), 0, equipped([MAUL, 0, 0, 0, 0, 0, 0])));
    refused(try_set(world, id, empty(), 0, equipped([MAUL, 102, 0, 0, 0, 0, 0])), TWO_HANDS);
    // An off-hand alone is worn.
    accepted(try_set(world, id, empty(), 0, equipped([0, 102, 0, 0, 0, 0, 0])));
}

// ---- the flattening (D-160, D-168)
// ---------------------------------------------------------------

// DS-2 (D-160, design/20 §6 test 3): `set_build` flattens the build and refuses it below the
// floors. A level 1 Vanguard's 100 health: one rune costing 75 leaves 25, accepted; two leave
// −50, refused (costs count on every rune, FX-43).
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 105882362)] // ceil(1.05 × 100840344 measured)
fn test_set_build_floor_refused() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    modifiers(world);
    fine_items(world, id);
    put_mods(world, 103, [(0, 0), (0, 0), (0, 0), (0, 0), (16, 1)]);
    put_mods(world, 104, [(0, 0), (0, 0), (0, 0), (0, 0), (16, 1)]);
    accepted(try_set(world, id, empty(), 0, chest(103)));
    refused(try_set(world, id, empty(), 0, equipped([0, 0, 103, 104, 0, 0, 0])), MAX_HEALTH);
}

// DS-23 (D-160): an insignia is worn on the piece its record names; one made for the chest is
// refused on the legs.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 105447333)] // ceil(1.05 × 100426031 measured)
fn test_set_build_insignia_piece_refused() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    modifiers(world);
    fine_items(world, id);
    put_mods(world, 103, [(0, 0), (0, 0), (0, 0), (17, 3), (0, 0)]);
    put_mods(world, 104, [(0, 0), (0, 0), (0, 0), (17, 3), (0, 0)]);
    accepted(try_set(world, id, empty(), 0, chest(103)));
    refused(try_set(world, id, empty(), 0, equipped([0, 0, 0, 104, 0, 0, 0])), INSIGNIA_PIECE);
}

// The flattening's checks of the whole build (design/20 §1.2, DS-1): six runes are more than an
// adventurer holds, refused.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 110452834)] // ceil(1.05 × 105193175 measured)
fn test_set_build_sixth_rune_refused() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    modifiers(world);
    fine_items(world, id);
    for entity in 101..107_u32 {
        put_mods(world, entity, [(0, 0), (0, 0), (0, 0), (0, 0), (11, 7)]);
    }
    accepted(try_set(world, id, empty(), 0, equipped([0, 102, 103, 104, 105, 106, 0])));
    refused(
        try_set(world, id, empty(), 0, equipped([101, 102, 103, 104, 105, 106, 0])), SOURCE_COUNT,
    );
}

// A modifier the registry does not hold is refused.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 100801606)] // ceil(1.05 × 96001529 measured)
fn test_set_build_unknown_modifier_refused() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    modifiers(world);
    fine_items(world, id);
    put_mods(world, 103, [(0, 0), (0, 0), (0, 0), (0, 0), (18, 1)]);
    refused(try_set(world, id, empty(), 0, chest(103)), NO_MODIFIER);
}

// CBT-02c (D-166): the registry checked each record's bounds, so a worn modifier must be what its
// record allows: in the slot of its record's type (a rune, 11, in the insignia's slot is refused),
// its benefit at a value of its record's range (armor against fire 1…7: 7 accepted, 8 and 0
// refused).
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 109646362)] // ceil(1.05 × 104425106 measured)
fn test_set_build_modifier_slot_and_value_refused() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    modifiers(world);
    fine_items(world, id);
    put_mods(world, 103, [(0, 0), (0, 0), (0, 0), (11, 7), (0, 0)]);
    refused(try_set(world, id, empty(), 0, chest(103)), SLOT_TYPE);
    put_mods(world, 103, [(0, 0), (0, 0), (0, 0), (0, 0), (11, 8)]);
    refused(try_set(world, id, empty(), 0, chest(103)), MODIFIER_VALUE);
    put_mods(world, 103, [(0, 0), (0, 0), (0, 0), (0, 0), (11, 0)]);
    refused(try_set(world, id, empty(), 0, chest(103)), MODIFIER_VALUE);
    put_mods(world, 103, [(0, 0), (0, 0), (0, 0), (0, 0), (11, 7)]);
    accepted(try_set(world, id, empty(), 0, chest(103)));
}

// AC-1 (D-168), design/20 §6 test 2's max-health build as items hold it: a level 20 Vanguard, +30
// health on the sword's and the shield's five held slots, insignias of 15, 10, 5, 5, 5 on the
// pieces (DS-23), five +50 health runes of distinct ids. 480 + 150 + 40 + 250 = 920 (the set
// bonuses of the envelope's 1,020 are not laid out yet). The words stored are the flattening's.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 112116461)] // ceil(1.05 × 106777581 measured)
fn test_set_build_stores_the_extremal_max_health() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    set_profile(world, id, 20, 2, 0);
    fine_items(world, id);
    start_cheat_caller_address(world.registry, addr(ADMIN));
    let admin = IRegistryAdminDispatcher { contract_address: world.registry };
    let none: Passive = Default::default();
    let health = |value: i16| PassiveTrait::new(passive_id::MAX_HEALTH, 0, 0, 0, 1, value);
    let held = [
        modifier_slot::PREFIX, modifier_slot::SUFFIX, modifier_slot::INSCRIPTION,
        modifier_slot::SUFFIX, modifier_slot::INSCRIPTION,
    ];
    let mut id_next: u32 = 1;
    for slot in held.span() {
        admin.set_record(MODIFIER, id_next, ModifierTrait::new(*slot, health(30), none).pack());
        id_next += 1;
    }
    let insignias = [15_i16, 10, 5, 5, 5];
    let mut piece: u8 = 3;
    for value in insignias.span() {
        admin
            .set_record(
                MODIFIER, id_next, ModifierTrait::insignia(piece, health(*value), none).pack(),
            );
        id_next += 1;
        piece += 1;
    }
    for _ in 0..5_u8 {
        admin
            .set_record(
                MODIFIER, id_next, ModifierTrait::new(modifier_slot::RUNE, health(50), none).pack(),
            );
        id_next += 1;
    }
    put_mods(world, 101, [(1, 30), (2, 30), (3, 30), (0, 0), (0, 0)]);
    put_mods(world, 102, [(0, 0), (4, 30), (5, 30), (0, 0), (0, 0)]);
    let mut k: u16 = 0;
    while k < 5 {
        let value: u8 = (*insignias.span()[k.into()]).try_into().unwrap();
        put_mods(world, 103 + k.into(), [(0, 0), (0, 0), (0, 0), (6 + k, value), (11 + k, 50)]);
        k += 1;
    }
    set(world, id, empty(), 0, equipped([101, 102, 103, 104, 105, 106, 107]));
    let ids = array![1_u16, 2, 3, 4, 5, 6, 11, 7, 12, 8, 13, 9, 14, 10, 15].span();
    let expected = flattened(world, id, 20, ids, [0; 4], [0; 4]);
    let stored = stored_snapshot(world, id);
    assert(stored == expected, 'the flattening stored');
    let (stats, _, _) = stored;
    assert(MemberStatsTrait::unpack(stats).max_health == 920, 'max health 920');
}

// Fix loop 1, AC-1: design/20 §6 test 2's max-energy build as `set_build` can hold it today: a
// level 20 Arcanist in light armor, the sword's and the shield's five held slots at +5, and a +3
// rune for its primary attribute on the chest: 30 + 20 + 25 = 75. The rune is stored but adds no
// rank: `BuildTrait::loadout` passes no attribute point (D-157 A: the global ids runes name are
// not numbered), so Wellspring's 45 (and the ranks' extremum, 15) is the library's alone
// (`test_extremal_max_energy_through_the_library`: 120); the set bonuses' 10 no item holds. The
// words stored are the flattening's.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 94791351)] // ceil(1.05 × 90277477 measured)
fn test_set_build_stores_the_extremal_max_energy() {
    let world = setup();
    let id = adventurer(world, ARCANIST);
    set_profile(world, id, 20, 2, 0);
    fine_items(world, id);
    start_cheat_caller_address(world.registry, addr(ADMIN));
    let admin = IRegistryAdminDispatcher { contract_address: world.registry };
    let none: Passive = Default::default();
    let energy = PassiveTrait::new(passive_id::MAX_ENERGY, 0, 0, 0, 1, 5);
    let held = [
        modifier_slot::PREFIX, modifier_slot::SUFFIX, modifier_slot::INSCRIPTION,
        modifier_slot::SUFFIX, modifier_slot::INSCRIPTION,
    ];
    let mut next: u32 = 1;
    for slot in held.span() {
        admin.set_record(MODIFIER, next, ModifierTrait::new(*slot, energy, none).pack());
        next += 1;
    }
    let attribute = PassiveTrait::new(passive_id::ATTRIBUTE, 13, 0, 0, 1, 3);
    admin.set_record(MODIFIER, 6, ModifierTrait::new(modifier_slot::RUNE, attribute, none).pack());
    put_mods(world, 101, [(1, 5), (2, 5), (3, 5), (0, 0), (0, 0)]);
    put_mods(world, 102, [(0, 0), (4, 5), (5, 5), (0, 0), (0, 0)]);
    put_mods(world, 103, [(0, 0), (0, 0), (0, 0), (0, 0), (6, 3)]);
    set(world, id, empty(), 0, equipped([101, 102, 103, 0, 0, 0, 0]));
    let expected = flattened(world, id, 20, array![1_u16, 2, 3, 4, 5, 6].span(), [0; 4], [0; 4]);
    let stored = stored_snapshot(world, id);
    assert(stored == expected, 'the flattening stored');
    let (stats, _, _) = stored;
    assert(MemberStatsTrait::unpack(stats).max_energy == 75, 'max energy 75');
}

// ---- the flattening's input kinds, as `set_build` asks for them (D-169, CBT-02f fix loop 1)
// ----------------------------------------------------------

/// A registry in front of the real one, for `test_set_build_requests_the_input_kinds`: it answers
/// every read by forwarding it, and records the kinds of the records each `bundle` call asks for,
/// one bit per kind, in the slot `kinds`. `bundle` is a view of the interface; it records through
/// the storage syscall, which Starknet runs in a call that is not static (`Hub`'s `bundle` call is
/// an ordinary call).
#[starknet::contract]
mod RecordingRegistry {
    use grimworld_logic::interface::{
        IRegistryRead, IRegistryReadDispatcher, IRegistryReadDispatcherTrait,
    };
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::storage_access::{storage_address_from_base, storage_base_address_from_felt252};
    use starknet::syscalls::{storage_read_syscall, storage_write_syscall};
    use starknet::{ContractAddress, SyscallResultTrait};

    #[storage]
    struct Storage {
        registry: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, registry: ContractAddress) {
        self.registry.write(registry);
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn real(self: @ContractState) -> IRegistryReadDispatcher {
            IRegistryReadDispatcher { contract_address: self.registry.read() }
        }
    }

    #[abi(embed_v0)]
    impl ReadImpl of IRegistryRead<ContractState> {
        fn record(self: @ContractState, kind: u8, id: u32) -> Span<felt252> {
            self.real().record(kind, id)
        }
        fn records(self: @ContractState, kind: u8, ids: Span<u32>) -> Span<felt252> {
            self.real().records(kind, ids)
        }
        fn bundle(self: @ContractState, requests: Span<(u8, u32)>) -> (u32, u32, Span<felt252>) {
            let address = storage_address_from_base(
                storage_base_address_from_felt252(selector!("kinds")),
            );
            let mut kinds: u256 = storage_read_syscall(0, address).unwrap_syscall().into();
            for request in requests {
                let (kind, _) = *request;
                let mut bit: u256 = 1;
                for _ in 0..kind {
                    bit *= 2;
                }
                kinds = kinds | bit;
            }
            storage_write_syscall(0, address, kinds.try_into().unwrap()).unwrap_syscall();
            self.real().bundle(requests)
        }
        fn content_version(self: @ContractState) -> u32 {
            self.real().content_version()
        }
    }
}

// D-169 (fix loop 1, quality 3): the kinds `Registry` counts as the flattening's inputs
// (`Inputs::includes`) are exactly the kinds `set_build` asks the registry for, recorded in front
// of the registry on the worst case of ENG-01 §9.3 (8 skills, 4 potions, 7 pieces holding 15
// modifiers), which asks for every kind `set_build` can ask for. A lot that makes `set_build` read
// another kind fails here until `Inputs::includes` names it.
#[test]
// gas: raised, ENG-R1a (D-144): the store's map addresses, a larger Hub class
#[available_gas(l2_gas: 120529768)] // ceil(1.05 × 114790255 measured)
fn test_set_build_requests_the_input_kinds() {
    let world = setup();
    let class = declare("RecordingRegistry").unwrap().contract_class();
    let (recorder, _) = class.deploy(@array![world.registry.into()]).unwrap();
    let flatten = read(world.hub, selector!("flatten"));
    start_cheat_caller_address(world.hub, addr(ADMIN));
    IHubAdminDispatcher { contract_address: world.hub }
        .set_contracts(recorder, addr(3), addr(4), addr(5), flatten.try_into().unwrap());
    let id = adventurer(world, VANGUARD);
    set_profile(world, id, 20, 2, 0);
    widest_equipment(world, id);
    // `create_adventurer` reads its region and its profession's kit (D-309) in one `bundle`:
    // neither is an input of the flattening; the record starts again for `set_build`.
    let created: u256 = read(recorder, selector!("kinds")).into();
    assert(created == 0x2 + 0x20000000, 'create: region and kit');
    store(recorder, selector!("kinds"), array![0].span());
    act(world, ALICE)
        .set_build(
            id,
            build([1, 2, 3, ELITE, 5, 6, 7, 8], [12, 12, 3, 0, 0, 0, 0, 0, 0], 3),
            belt([1, 8, 15, 22], [3, 3, 3, 3]),
            equipped([101, 102, 103, 104, 105, 106, 107]),
        );
    let requested: u256 = read(recorder, selector!("kinds")).into();
    let mut accepted: u256 = 0;
    let mut bit: u256 = 2;
    for kind in 1..LAST_KIND + 1 {
        if Inputs::includes(kind) {
            accepted += bit;
        }
        bit *= 2;
    }
    assert(requested == accepted, 'requested kinds != inputs');
}

// ---- `buy_skill`, the hub's skill trainer (SKILL-01, D-275)
// --------------------------------------------------------------

/// The budget of the `buy_skill` call alone in its worst case (a hub action's target is its
/// measure, D-158 (c)): the 21st skill, the price's count at its cap. snforge, `get_available_gas`
/// around the dispatcher call: ceil(1.05 × 760,000 measured). ENG-01 §10's row is the node's
/// measure (D-279): 1,600,960 initialised, 2,002,960 cold.
const BUY_SKILL_CALL: u128 = 798000;

fn gold_key(id: u32) -> felt252 {
    map_entry_address(selector!("gold"), array![OwnerTrait::key(PACK, id)].span())
}
/// `amount` gold in the pack of `id`, as a report credits it.
fn set_gold(world: World, id: u32, amount: u64) {
    write(world.hub, gold_key(id), StorePacking::pack(Gold { amount }));
}
fn gold_of(world: World, id: u32) -> u64 {
    let gold: Gold = StorePacking::unpack(read(world.hub, gold_key(id)));
    gold.amount
}
fn known_key(id: u32) -> felt252 {
    map_entry_address(selector!("known_skills"), array![id.into(), 0].span())
}
/// Alice's Vanguard with `adventurer`'s fixtures, knowing no skill.
fn learner(world: World) -> u32 {
    let id = adventurer(world, VANGUARD);
    write(world.hub, known_key(id), 0);
    id
}
fn try_buy(world: World, who: felt252, id: u32, skill: u16) -> Result<(), Array<felt252>> {
    #[feature("safe_dispatcher")]
    let result = try_act(world, who).buy_skill(id, skill);
    result
}

// Who may call (ENG-01 §4.3, design/16): the adventurer's owner, in a hub; nothing is written.
#[test]
#[available_gas(l2_gas: 80859566)] // ceil(1.05 × 77009110 measured)
fn test_buy_skill_ownership_refusals() {
    let world = setup();
    let id = learner(world);
    set_gold(world, id, 1000);
    refused(try_buy(world, ALICE, 9, 1), NO_ADVENTURER);
    refused(try_buy(world, BOB, id, 1), NOT_OWNER);
    // Inside an instance, not in a hub: the trainer is a hub's (design/03).
    let place = read(world.hub, adventurer_word(id, 1));
    write(world.hub, adventurer_word(id, 1), place + 0x1000000000000000000000000);
    refused(try_buy(world, ALICE, id, 1), NOT_IN_HUB);
    write(world.hub, adventurer_word(id, 1), place);
    let core = core_of(world, id);
    write(
        world.hub, adventurer_word(id, 0), StorePacking::pack(AdventurerCore { status: 1, ..core }),
    );
    refused(try_buy(world, ALICE, id, 1), ADVENTURER_DELETED);
    write(world.hub, adventurer_word(id, 0), StorePacking::pack(core));
    assert(gold_of(world, id) == 1000 && read(world.hub, known_key(id)) == 0, 'nothing written');
    accepted(try_buy(world, ALICE, id, 1));
}

// The skill is in the registry's content (`SKILL`): a skill with no record is not sold.
#[test]
#[available_gas(l2_gas: 79510379)] // ceil(1.05 × 75724170 measured)
fn test_buy_skill_not_in_content() {
    let world = setup();
    let id = learner(world);
    set_gold(world, id, 1000);
    refused(try_buy(world, ALICE, id, NO_RECORD), SKILL_NOT_SOLD);
    refused(try_buy(world, ALICE, id, 0), SKILL_NOT_SOLD);
    // Past page 255: no record either.
    refused(try_buy(world, ALICE, id, 65000), SKILL_NOT_SOLD);
    assert(gold_of(world, id) == 1000 && read(world.hub, known_key(id)) == 0, 'nothing written');
}

// A skill already known is not sold twice.
#[test]
#[available_gas(l2_gas: 79269089)] // ceil(1.05 × 75494370 measured)
fn test_buy_skill_already_known() {
    let world = setup();
    let id = adventurer(world, VANGUARD); // knows 1 to 12
    set_gold(world, id, 1000);
    refused(try_buy(world, ALICE, id, 3), SKILL_ALREADY_KNOWN);
    refused(try_buy(world, ALICE, id, ARCANIST_SKILL), SKILL_ALREADY_KNOWN);
    assert(gold_of(world, id) == 1000 && read(world.hub, known_key(id)) == 0x1ffe + LIVE, 'kept');
}

// The pack's gold pays the price: one gold short is refused, the exact price bought.
#[test]
#[available_gas(l2_gas: 80153346)] // ceil(1.05 × 76336520 measured)
fn test_buy_skill_not_affordable() {
    let world = setup();
    let id = learner(world);
    refused(try_buy(world, ALICE, id, 1), SKILL_PRICE);
    set_gold(world, id, 49);
    refused(try_buy(world, ALICE, id, 1), SKILL_PRICE);
    assert(gold_of(world, id) == 49 && read(world.hub, known_key(id)) == 0, 'nothing written');
    set_gold(world, id, 50);
    accepted(try_buy(world, ALICE, id, 1));
    assert(gold_of(world, id) == 0, 'the exact price');
}

// Bought: the price debited, the skill known, and `set_build` puts it on the bar; the second skill
// charges the second price (60).
#[test]
#[available_gas(l2_gas: 88107889)] // ceil(1.05 × 83912275 measured)
fn test_buy_skill_then_set_build() {
    let world = setup();
    let id = learner(world);
    set_gold(world, id, 110);
    refused(try_set(world, id, bar([1, 0, 0, 0, 0, 0, 0, 0]), 0, 0), SKILL_NOT_KNOWN);
    act(world, ALICE).buy_skill(id, 1);
    assert(gold_of(world, id) == 60, 'first price 50');
    assert(read(world.hub, known_key(id)) == 0x2 + LIVE, 'skill 1 known');
    accepted(try_set(world, id, bar([1, 0, 0, 0, 0, 0, 0, 0]), 0, 0));
    act(world, ALICE).buy_skill(id, 2);
    assert(gold_of(world, id) == 0, 'second price 60');
    assert(read(world.hub, known_key(id)) == 0x6 + LIVE, 'skills 1 and 2 known');
    accepted(try_set(world, id, bar([1, 2, 0, 0, 0, 0, 0, 0]), 0, 0));
    // The third costs 70.
    refused(try_buy(world, ALICE, id, 3), SKILL_PRICE);
}

// The worst case: 20 skills known (the price's count at its cap), the 21st costs 1,000, and so
// does the 22nd. The call alone carries its own budget.
#[test]
#[available_gas(l2_gas: 79729062)] // ceil(1.05 × 75932440 measured)
fn test_buy_skill_worst_case() {
    let world = setup();
    let id = learner(world);
    // Skills 12 to 31 known: 20 skills, none of the registry's 1 to 11.
    write(world.hub, known_key(id), 0xfffff000 + LIVE);
    set_gold(world, id, 2000);
    let hub = act(world, ALICE);
    let gas = get_available_gas();
    hub.buy_skill(id, ARCANIST_SKILL);
    let call = gas - get_available_gas();
    println!("gas buy_skill, worst case (the 21st skill): {}", call);
    assert(call <= BUY_SKILL_CALL, 'buy_skill over its budget');
    assert(gold_of(world, id) == 1000, '21st price 1000');
    hub.buy_skill(id, WARDEN_SKILL);
    assert(gold_of(world, id) == 0, '22nd price 1000');
    assert(read(world.hub, known_key(id)) == 0xfffff000 + 0xc00 + LIVE, '10 and 11 known');
}

// ---- The creation kit (D-309, CNT-01): `create_adventurer` reads its profession's `KIT`
// --------------------------------------------------------------------------------------

/// Writes `profession`'s kit: no weapon, `skills` (registry ids of that profession).
fn write_kit(world: World, profession: u8, skills: [u16; 6]) {
    start_cheat_caller_address(world.registry, addr(ADMIN));
    IRegistryAdminDispatcher { contract_address: world.registry }
        .set_record(KIT, profession.into(), KitTrait::new(0, skills).pack());
}

/// Alice's new adventurer of `profession`, her account registered at the first one.
fn created(world: World, profession: u8, first: bool) -> u32 {
    let hub = act(world, ALICE);
    if first {
        hub.register();
    }
    hub.create_adventurer('Aldric', profession)
}

// The purse is the price of the starter skills the kit names, bought from none known (450 for
// design/03's six: 50 + 60 + 70 + 80 + 90 + 100), read from the content: a kit naming one skill
// gives 50, a kit naming none gives no gold, and so does a profession without a `KIT`.
#[test]
#[available_gas(l2_gas: 80673306)] // ceil(1.05 × 76831720 measured)
fn test_create_adventurer_kit_purse() {
    let world = setup();
    let none = created(world, VANGUARD, true);
    assert(gold_of(world, none) == 0, 'no kit, no purse');
    write_kit(world, VANGUARD, [1, 2, 3, 4, 5, 6]);
    write_kit(world, WARDEN, [10, 0, 0, 0, 0, 0]);
    write_kit(world, ARCANIST, [0; 6]);
    let vanguard = created(world, VANGUARD, false);
    let warden = created(world, WARDEN, false);
    assert(gold_of(world, vanguard) == 450, 'six skills: 450');
    assert(gold_of(world, warden) == 50, 'one skill: 50');
    let bob = act(world, BOB);
    bob.register();
    let arcanist = bob.create_adventurer('Brenna', ARCANIST);
    assert(gold_of(world, arcanist) == 0, 'a kit of none: 0');
}

// The purse buys exactly the six starter skills and leaves 0: a seventh is refused.
#[test]
#[available_gas(l2_gas: 70383164)] // ceil(1.05 × 67031584 measured)
fn test_create_adventurer_purse_buys_the_bar() {
    let world = setup();
    write_kit(world, VANGUARD, [1, 2, 3, 4, 5, 6]);
    let id = created(world, VANGUARD, true);
    for skill in 1..7_u16 {
        accepted(try_buy(world, ALICE, id, skill));
    }
    assert(gold_of(world, id) == 0, 'the purse spent');
    refused(try_buy(world, ALICE, id, 7), SKILL_PRICE);
}

// The kit is content (pillar 6): rewriting the record changes what a new adventurer receives,
// with no code change; one already created keeps its purse.
#[test]
#[available_gas(l2_gas: 69674042)] // ceil(1.05 × 66356230 measured)
fn test_create_adventurer_kit_is_content() {
    let world = setup();
    write_kit(world, VANGUARD, [1, 2, 3, 4, 5, 6]);
    let before = created(world, VANGUARD, true);
    write_kit(world, VANGUARD, [1, 2, 3, 0, 0, 0]);
    let after = created(world, VANGUARD, false);
    assert(gold_of(world, before) == 450, 'kept');
    assert(gold_of(world, after) == 50 + 60 + 70, 'three skills: 180');
    let parts = IRegistryReadDispatcher { contract_address: world.registry }.record(KIT, 1);
    assert(KitRecord::unpack(parts).count() == 3, 'the record read');
}

// D-144: `create_adventurer`'s cost with a six-skill kit against none, initialised (the list's
// page exists): the `bundle` of the region and the kit, and the purse's new gold slot.
#[test]
#[available_gas(l2_gas: 71763920)] // ceil(1.05 × 68346590 measured)
fn test_gas_create_adventurer_kit() {
    let world = setup();
    let hub = act(world, ALICE);
    hub.register();
    hub.create_adventurer('Aldric', ARCANIST);
    let gas = get_available_gas();
    hub.create_adventurer('Aldric', ARCANIST);
    println!("gas create_adventurer initialised, no kit: {}", gas - get_available_gas());
    write_kit(world, WARDEN, [10, 0, 0, 0, 0, 0]);
    start_cheat_caller_address(world.hub, addr(ALICE));
    let gas = get_available_gas();
    hub.create_adventurer('Aldric', WARDEN);
    println!(
        "gas create_adventurer initialised, a kit and its purse: {}", gas - get_available_gas(),
    );
}

fn try_delete(world: World, id: u32) -> Result<(), Array<felt252>> {
    #[feature("safe_dispatcher")]
    let result = try_act(world, ALICE).delete_adventurer(id);
    result
}

// D-310: the kit is forfeited at deletion. A new adventurer holding its purse, whole or partly
// spent, is deleted and its gold dropped; gold above the purse is refused, as is any gold of a
// profession without a kit.
#[test]
#[available_gas(l2_gas: 84040949)] // ceil(1.05 × 80038999 measured)
fn test_delete_adventurer_forfeits_the_purse() {
    let world = setup();
    write_kit(world, VANGUARD, [1, 2, 3, 4, 5, 6]);
    let whole = created(world, VANGUARD, true);
    accepted(try_delete(world, whole));
    assert(gold_of(world, whole) == 0, 'the purse dropped');
    let spent = created(world, VANGUARD, false);
    accepted(try_buy(world, ALICE, spent, 1));
    accepted(try_buy(world, ALICE, spent, 2));
    assert(gold_of(world, spent) == 450 - 50 - 60, 'part spent');
    accepted(try_delete(world, spent));
    assert(gold_of(world, spent) == 0, 'the rest dropped');
    let richer = created(world, VANGUARD, false);
    set_gold(world, richer, 451);
    refused(try_delete(world, richer), PACK_HOLDS_GOLD);
    set_gold(world, richer, 0);
    accepted(try_delete(world, richer));
    let none = created(world, WARDEN, false);
    set_gold(world, none, 1);
    refused(try_delete(world, none), PACK_HOLDS_GOLD);
    assert(gold_of(world, none) == 1, 'kept on a refusal');
}

// ---- The kit's weapon (WPN-01, D-309, D-310): created by `create_item`, worn by `set_build`,
// forfeited at deletion
// --------------------------------------------------------------------------------------

/// Skills 12 to 16: the Vanguard's Axes attacks (attribute 3) and the Warden's Archery attacks
/// (attribute 7), as the seed's starter attacks are (Cleave, Gash, Haft Blow; Aimed Shot,
/// Hamstring Shot); the fixtures' skills 1 to 11 name attribute 1. The bases: 1 design/15's axe,
/// 2 its bow (`BASE`, written after the skills).
const AXES_ATTACKS: [u16; 3] = [12, 13, 14];
const ARCHERY_ATTACKS: [u16; 2] = [15, 16];
fn axe_base() -> Base {
    BaseTrait::weapon(1, weapon::AXE, 9, 17, 1, 1, damage::SLASHING, 3)
}
fn bow_base() -> Base {
    BaseTrait::weapon(2, weapon::BOW, 11, 21, 2, 6, damage::PIERCING, 7)
}

fn weapon_kits(world: World) {
    start_cheat_caller_address(world.registry, addr(ADMIN));
    let admin = IRegistryAdminDispatcher { contract_address: world.registry };
    let none = [Default::default(); 3];
    for attribute in array![3_u8, 3, 3, 7, 7] {
        let profession = if attribute == 3 {
            VANGUARD
        } else {
            WARDEN
        };
        let attack = SkillTrait::new(
            profession, attribute, skill_kind::ATTACK, 5, 0, 1, 8, 1, 1, false, none,
        );
        admin.set_record(SKILL, admin.last_id(SKILL).try_into().unwrap() + 1, attack.pack());
    }
    admin.set_record(BASE, 1, axe_base().pack());
    admin.set_record(BASE, 2, bow_base().pack());
    admin.set_record(KIT, VANGUARD.into(), KitTrait::new(1, [12, 13, 14, 1, 0, 0]).pack());
    admin.set_record(KIT, WARDEN.into(), KitTrait::new(2, [15, 16, 10, 0, 0, 0]).pack());
    admin.set_record(KIT, ARCANIST.into(), KitTrait::new(0, [11, 0, 0, 0, 0, 0]).pack());
}

fn pack_key(id: u32, page: u8) -> felt252 {
    map_entry_address(selector!("packs"), array![id.into(), page.into()].span())
}
fn item_key(entity: u32) -> felt252 {
    map_entry_address(selector!("items"), array![entity.into()].span())
}
/// The entity in lane 0 of `id`'s pack list, 0 for none.
fn first_entity(world: World, id: u32) -> u32 {
    let page = read(world.hub, pack_key(id, 0));
    if page == 0 {
        return 0;
    }
    let lanes: Lanes32 = StorePacking::unpack(page);
    *lanes.lanes.span()[0]
}
fn item_base_of(world: World, entity: u32) -> ItemBase {
    StorePacking::unpack(read(world.hub, item_key(entity)))
}
/// Skills 1 to 16 known.
fn know_all(world: World, id: u32) {
    write(world.hub, known_key(id), 0x1fffe + LIVE);
}

// Each profession's new adventurer holds its kit's weapon, a common item at requirement 0 of its
// base, the base's weapon copied (D-158), created by `create_item` in lane 0 of its pack; the
// Arcanist's kit names none, and nothing is created.
#[test]
#[available_gas(l2_gas: 92070080)] // ceil(1.05 × 87685790 measured)
fn test_create_adventurer_kit_weapon() {
    let world = setup();
    weapon_kits(world);
    let vanguard = created(world, VANGUARD, true);
    let warden = created(world, WARDEN, false);
    let arcanist = created(world, ARCANIST, false);
    let axe = first_entity(world, vanguard);
    let bow = first_entity(world, warden);
    assert(axe == 1 && bow == 2, 'entities 1 and 2, in order');
    let expected = ItemBaseTrait::new(1, @axe_base(), 0, COMMON, 0, 0, 0, 0, PACK, vanguard);
    assert(item_base_of(world, axe) == expected, 'the axe');
    assert(item_base_of(world, axe).weapon().damage == 9, 'its damage at 0');
    let expected = ItemBaseTrait::new(2, @bow_base(), 0, COMMON, 0, 0, 0, 0, PACK, warden);
    assert(item_base_of(world, bow) == expected, 'the bow');
    assert(first_entity(world, arcanist) == 0, 'no weapon');
    assert(read(world.hub, item_key(3)) == 0, 'no third item');
}

// The kit is content: the Vanguard's record rewritten to name the bow gives the next Vanguard a
// bow, with no code change; one created before keeps its axe.
#[test]
#[available_gas(l2_gas: 88309799)] // ceil(1.05 × 84104570 measured)
fn test_create_adventurer_kit_weapon_is_content() {
    let world = setup();
    weapon_kits(world);
    let before = created(world, VANGUARD, true);
    start_cheat_caller_address(world.registry, addr(ADMIN));
    IRegistryAdminDispatcher { contract_address: world.registry }
        .set_record(KIT, VANGUARD.into(), KitTrait::new(2, [12, 0, 0, 0, 0, 0]).pack());
    let after = created(world, VANGUARD, false);
    assert(item_base_of(world, first_entity(world, before)).base == 1, 'kept its axe');
    assert(item_base_of(world, first_entity(world, after)).base == 2, 'a bow now');
}

// `set_build` wearing the kit's weapon fills the snapshot's weapon (its base's, at requirement 0,
// met) and sets CBT-05f's weapon-required bit on every attack skill of another attribute: the
// Vanguard's three Axes attacks pass with the axe, the fixtures' attack (skill 1, attribute 1)
// does not; without a weapon every attack is bound. The Warden's Archery attacks likewise.
#[test]
#[available_gas(l2_gas: 101511335)] // ceil(1.05 × 96677461 measured)
fn test_set_build_wears_the_kit_weapon() {
    let world = setup();
    weapon_kits(world);
    let vanguard = created(world, VANGUARD, true);
    know_all(world, vanguard);
    let axe = first_entity(world, vanguard);
    set(world, vanguard, bar([12, 13, 14, 1, 0, 0, 0, 0]), 0, equipped([axe, 0, 0, 0, 0, 0, 0]));
    let (stats, _, _) = stored_snapshot(world, vanguard);
    let stats = MemberStatsTrait::unpack(stats);
    assert(stats.weapon == weapon::AXE && stats.weapon_damage == 9, 'axe, 9');
    assert(stats.weapon_ticks == 1 && stats.weapon_range == 1, 'one tick, range 1');
    assert(stats.damage_type == damage::SLASHING && stats.requirement_met == 1, 'slashing, met');
    assert(stats.weapon_required == 0b1000, 'only skill 1 bound');
    set(world, vanguard, bar([12, 13, 14, 1, 0, 0, 0, 0]), 0, 0);
    let (stats, _, _) = stored_snapshot(world, vanguard);
    let stats = MemberStatsTrait::unpack(stats);
    assert(stats.weapon == 0 && stats.weapon_damage == 0, 'no weapon');
    assert(stats.weapon_required == 0b1111, 'every attack bound');

    let warden = created(world, WARDEN, false);
    know_all(world, warden);
    let bow = first_entity(world, warden);
    set(world, warden, bar([15, 16, 10, 0, 0, 0, 0, 0]), 0, equipped([bow, 0, 0, 0, 0, 0, 0]));
    let (stats, _, _) = stored_snapshot(world, warden);
    let stats = MemberStatsTrait::unpack(stats);
    assert(stats.weapon == weapon::BOW && stats.weapon_damage == 11, 'bow, 11');
    assert(stats.weapon_ticks == 2 && stats.weapon_range == 6, 'two ticks, range 6');
    assert(stats.damage_type == damage::PIERCING, 'piercing');
    assert(stats.weapon_required == 0b100, 'only skill 10 bound');
}

// D-310: the kit's weapon is forfeited at deletion with the purse, worn or not: the pack's list
// and what it wears are emptied, the item kept, held by nobody. Another item beside it, or an
// item of another base alone, is still refused.
#[test]
#[available_gas(l2_gas: 109067783)] // ceil(1.05 × 103874079 measured)
fn test_delete_adventurer_forfeits_the_kit_weapon() {
    let world = setup();
    weapon_kits(world);
    let held = created(world, VANGUARD, true);
    let axe = first_entity(world, held);
    accepted(try_delete(world, held));
    assert(first_entity(world, held) == 0 && gold_of(world, held) == 0, 'pack emptied');
    let item = item_base_of(world, axe);
    assert(item.owner_kind == 0 && item.owner == 0 && item.base == 1, 'held by nobody');

    let worn = created(world, VANGUARD, false);
    know_all(world, worn);
    let axe = first_entity(world, worn);
    set(world, worn, bar([12, 0, 0, 0, 0, 0, 0, 0]), 0, equipped([axe, 0, 0, 0, 0, 0, 0]));
    accepted(try_delete(world, worn));
    let equipped_word = read(world.hub, adventurer_word(worn, 4));
    assert(equipped_word == LIVE && first_entity(world, worn) == 0, 'unworn, emptied');

    let more = created(world, VANGUARD, false);
    let page = StorePacking::pack(
        Lanes32 { lanes: [first_entity(world, more), 101, 0, 0, 0, 0, 0] },
    );
    write(world.hub, pack_key(more, 0), page);
    refused(try_delete(world, more), PACK_HOLDS_EQUIPMENT);

    let other = created(world, VANGUARD, false);
    put_item(world, 120, 2, 0, 0, PACK, other);
    let page = StorePacking::pack(Lanes32 { lanes: [120, 0, 0, 0, 0, 0, 0] });
    write(world.hub, pack_key(other, 0), page);
    refused(try_delete(world, other), PACK_HOLDS_EQUIPMENT);
}

// D-144: `create_adventurer`'s cost with a kit that names a weapon against the same kit without
// one, initialised: the `record(BASE)` call after the `bundle` and `create_item`'s writes
// (`next_item`, the item's base, the pack's first page).
#[test]
#[available_gas(l2_gas: 93230046)] // ceil(1.05 × 88790520 measured)
fn test_gas_create_adventurer_kit_weapon() {
    let world = setup();
    weapon_kits(world);
    let hub = act(world, ALICE);
    hub.register();
    hub.create_adventurer('Aldric', ARCANIST);
    start_cheat_caller_address(world.registry, addr(ADMIN));
    let admin = IRegistryAdminDispatcher { contract_address: world.registry };
    admin.set_record(KIT, WARDEN.into(), KitTrait::new(0, [15, 16, 10, 0, 0, 0]).pack());
    start_cheat_caller_address(world.hub, addr(ALICE));
    let gas = get_available_gas();
    let without = hub.create_adventurer('Aldric', WARDEN);
    println!(
        "gas create_adventurer initialised, a kit without weapon: {}", gas - get_available_gas(),
    );
    act(world, ALICE).delete_adventurer(without);
    start_cheat_caller_address(world.registry, addr(ADMIN));
    admin.set_record(KIT, WARDEN.into(), KitTrait::new(2, [15, 16, 10, 0, 0, 0]).pack());
    start_cheat_caller_address(world.hub, addr(ALICE));
    let gas = get_available_gas();
    hub.create_adventurer('Aldric', WARDEN);
    println!(
        "gas create_adventurer initialised, a kit with its weapon: {}", gas - get_available_gas(),
    );
}
