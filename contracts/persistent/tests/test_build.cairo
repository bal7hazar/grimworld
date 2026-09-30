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
use grimworld_logic::content::{ITEM, LOCATION, MODIFIER, REGION, SKILL};
use grimworld_logic::models::base::{Base, BaseTrait};
use grimworld_logic::models::item::{ItemRecord, ItemTrait, class};
use grimworld_logic::models::location::{LocationRecord, LocationTrait, kind as location_kind};
use grimworld_logic::models::modifier::{ModifierRecord, ModifierTrait, slot as modifier_slot};
use grimworld_logic::models::region::{RegionRecord, RegionTrait};
use grimworld_logic::models::skill::{SkillRecord, SkillTrait};
use grimworld_logic::packing::{LIVE, Lanes16, Lanes32};
use grimworld_logic::snapshot::errors::{
    INSIGNIA_PIECE, MAX_HEALTH, NO_MODIFIER, SLOT_TYPE, SOURCE_COUNT, VALUE as MODIFIER_VALUE,
};
use grimworld_logic::snapshot::{SnapshotBuildTrait, Worn, unpack_kit, unpack_stats};
use grimworld_logic::types::combat::damage;
use grimworld_logic::types::passive::{Passive, PassiveTrait, id as passive_id};
use grimworld_persistent::models::account::{PACK, VAULT, owner_key};
use grimworld_persistent::models::adventurer::errors::{
    ADVENTURER_DELETED, BELT_LAYOUT, BELT_NOT_IN_PACK, BUILD_LAYOUT, COUNT_WITHOUT_ITEM,
    DUPLICATE_ITEM, DUPLICATE_SKILL, ELITE_SLOT, EQUIPPED_LAYOUT, NOT_A_POTION, NOT_IN_HUB,
    NOT_OWNER, NO_ADVENTURER, NO_ATTRIBUTE, NO_SKILL, POINTS, RANK_ABOVE_12, SKILL_NOT_KNOWN,
    SKILL_PROFESSION, TWO_ELITES, TWO_HANDS, WRONG_SLOT,
};
use grimworld_persistent::models::adventurer::{AdventurerCore, Build, BuildTrait, NO_ELITE};
use grimworld_persistent::models::item::errors::{A_COMPONENT, NOT_IN_PACK, UNIDENTIFIED};
use grimworld_persistent::models::item::{
    COMPONENT, IDENTIFIED, ItemBaseTrait, ItemMods, ItemModsTrait, Modifier,
};
use grimworld_persistent::models::snapshot::StoredSnapshotTrait;
use grimworld_persistent::systems::hub::{
    IHubAdminDispatcher, IHubAdminDispatcherTrait, IHubDispatcher, IHubDispatcherTrait,
    IHubSafeDispatcher, IHubSafeDispatcherTrait,
};
use grimworld_persistent::systems::registry::{
    IRegistryAdminDispatcher, IRegistryAdminDispatcherTrait,
};
use grimworld_logic::interface::{IRegistryReadDispatcher, IRegistryReadDispatcherTrait};
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
/// Skills 1 to 12 known on page 0 (`buy_skill` is a later lot's).
fn know_skills(world: World, id: u32) {
    let key = map_entry_address(selector!("known_skills"), array![id.into(), 0].span());
    write(world.hub, key, 0x1ffe + LIVE);
}
/// `amount` of `item` in the pack of `id`, the page's other lanes kept.
fn give(world: World, id: u32, item: u32, amount: u32) {
    let key = map_entry_address(
        selector!("balances"), array![owner_key(PACK, id), (item / 7).into()].span(),
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

/// What the flattening makes of the build `set_build` stored for `id` (a Vanguard, not
/// personalised, the belt given), computed here from the same records: `SnapshotBuildTrait::words`
/// on the items 101–107 as they are worn, and the records of the modifiers `ids` read from the
/// registry. The kit word sealed with the registry's content version, as `set_build` stores it.
fn flattened(
    world: World, id: u32, level: u8, ids: Span<u16>, belt_items: [u32; 4], counts: [u8; 4],
) -> (felt252, felt252, felt252) {
    let build: Build = StorePacking::unpack(read(world.hub, adventurer_word(id, 2)));
    let loadout = build.loadout(level, VANGUARD, false, belt_items, counts);
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
    let registry = IRegistryReadDispatcher { contract_address: world.registry };
    let (version, parts) = registry.bundle(requests.span());
    let (stats, bar, kit) = SnapshotBuildTrait::words(@loadout, worn.span(), ids, parts);
    (stats, bar, StoredSnapshotTrait::seal(kit, version))
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
/// measured, no modifier worn): the flattening of the 15 modifiers, D-160, D-168.
const WORST_CASE_CALL: u128 = 8501927;

// The worst case of ENG-01 §9.3 and §10: 8 skills (an elite in slot 3), every attribute point of
// a level 20 Copper spent (12/12/3: 97 + 97 + 6 = 200), four potions on four pack pages, seven
// pieces worn holding the 15 modifiers design/20 §1.2 counts, flattened by `FlattenLibrary`
// (D-168). Writes: `build`, `belt`, `equipped`, overwritten, each the word sent plus `LIVE`; the
// snapshot's three words, new at the adventurer's first `set_build`, then overwritten (the second
// call). The words stored are the flattening's (AC-1).
#[test]
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 120038756)] // ceil(1.05 × 114322624 measured)
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
    println!("gas set_build, worst case, again (snapshot overwritten): {}", gas - get_available_gas());
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
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 86078618)] // ceil(1.05 × 81979636 measured)
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
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 82105517)] // ceil(1.05 × 78195730 measured)
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
    assert(unpack_stats(stats).max_health == 480, 'level 20 health');
    let version = IRegistryReadDispatcher { contract_address: world.registry }.content_version();
    assert(unpack_kit(StoredSnapshotTrait::kit(kit, version)).belt == [0; 4], 'no belt');
}

// ---- who, where, and the layouts
// -----------------------------------------------------------------

#[test]
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 79103875)] // ceil(1.05 × 75337023 measured)
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
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 81890680)] // ceil(1.05 × 77991123 measured)
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
// gas: raised, D-166: the Registry checks each record (CBT-02c), its class deploys dearer
#[available_gas(l2_gas: 75255054)] // ceil(1.05 × 71671480 measured)
fn test_bar_duplicate_refused() {
    let world = setup();
    let id = adventurer(world, VANGUARD);
    accepted(try_set(world, id, bar([1, 2, 3, 5, 6, 7, 8, 0]), 0, 0));
    refused(try_set(world, id, bar([1, 2, 3, 5, 6, 7, 8, 1]), 0, 0), DUPLICATE_SKILL);
    refused(try_set(world, id, bar([0, 2, 0, 0, 0, 0, 0, 2]), 0, 0), DUPLICATE_SKILL);
}

// Known: skills 1 to 12 on page 0; skill 13 is in no bit. 12 is known but has no record.
#[test]
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 83235061)] // ceil(1.05 × 79271486 measured)
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
// gas: raised, D-166: the Registry checks each record (CBT-02c), its class deploys dearer
#[available_gas(l2_gas: 76073099)] // ceil(1.05 × 72450570 measured)
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
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 83108764)] // ceil(1.05 × 79151203 measured)
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
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 82253752)] // ceil(1.05 × 78336906 measured)
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
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 97211525)] // ceil(1.05 × 92582404 measured)
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
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 89065472)] // ceil(1.05 × 84824259 measured)
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
// gas: raised, D-166: the Registry checks each record (CBT-02c), its class deploys dearer
#[available_gas(l2_gas: 77166852)] // ceil(1.05 × 73492240 measured)
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
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 82103696)] // ceil(1.05 × 78193996 measured)
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
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 86750370)] // ceil(1.05 × 82619400 measured)
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
// gas: raised, CBT-02e: set_build flattens through FlattenLibrary and stores the snapshot (D-168)
#[available_gas(l2_gas: 86393641)] // ceil(1.05 × 82279658 measured)
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

// ---- the flattening (D-160, D-168) ---------------------------------------------------------------

// DS-2 (D-160, design/20 §6 test 3): `set_build` flattens the build and refuses it below the
// floors. A level 1 Vanguard's 100 health: one rune costing 75 leaves 25, accepted; two leave
// −50, refused (costs count on every rune, FX-43).
#[test]
#[available_gas(l2_gas: 100288592)] // ceil(1.05 × 95512944 measured)
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
#[available_gas(l2_gas: 99874143)] // ceil(1.05 × 95118231 measured)
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
#[available_gas(l2_gas: 104694739)] // ceil(1.05 × 99709275 measured)
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
#[available_gas(l2_gas: 95454313)] // ceil(1.05 × 90908869 measured)
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
#[available_gas(l2_gas: 103839883)] // ceil(1.05 × 98895126 measured)
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
#[available_gas(l2_gas: 106239569)] // ceil(1.05 × 101180541 measured)
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
        admin.set_record(MODIFIER, id_next, ModifierTrait::insignia(piece, health(*value), none).pack());
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
    assert(unpack_stats(stats).max_health == 920, 'max health 920');
}
