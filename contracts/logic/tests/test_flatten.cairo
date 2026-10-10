// CBT-02e (D-168): the snapshot's flattening as a library class. `FlattenLibrary.words` through a
// `library_call` is `SnapshotBuildTrait::words`, whose unit tests are in `snapshot.cairo`; here,
// what needs the declared class: the call's result and its cost on the widest equipment design/20
// §1.2 counts (the benchmark of `Hub.set_build`'s flattening, D-158 (c)), and design/20 §6 test
// 2's extremal builds as far as items and a loadout hold them (fix loop 1): the library's words
// equal the direct flattening's, the field its extremum; what the item model cannot hold yet is
// said at each test.
use core::testing::get_available_gas;
use grimworld_logic::interface::{IFlattenLibraryDispatcherTrait, IFlattenLibraryLibraryDispatcher};
use grimworld_logic::models::base::slot as base_slot;
use grimworld_logic::models::index::Modifier;
use grimworld_logic::models::modifier::{ModifierRecord, ModifierTrait, slot as modifier_slot};
use grimworld_logic::snapshot::{Loadout, SnapshotBuildTrait, Worn, unpack_kit, unpack_stats};
use grimworld_logic::types::combat::damage;
use grimworld_logic::types::passive::{Passive, PassiveTrait, id};
use snforge_std::{DeclareResultTrait, declare};

/// The widest equipment of design/20 §1.2, as `Hub.set_build` reads it: the sword's prefix,
/// suffix and inscription (modifiers 1–3), the shield's suffix and inscription (4–5), each
/// piece's insignia (6–10, made for its piece) and rune (11–15): 15 modifiers, 30 passives
/// (life steal 1…5 or armor against fire 1…7, each costing 7 armor against cold).
fn widest() -> (Loadout, Span<Worn>, Span<u16>, Span<felt252>) {
    let cold = PassiveTrait::new(id::ARMOR_VS, damage::COLD, 0, 0, 7, 7);
    let steal = PassiveTrait::new(id::LIFE_STEAL_ON_HIT, 0, 0, 0, 1, 5);
    let fire = PassiveTrait::new(id::ARMOR_VS, damage::FIRE, 0, 0, 1, 7);
    let mut records: Array<Modifier> = array![
        ModifierTrait::new(modifier_slot::PREFIX, steal, cold),
        ModifierTrait::new(modifier_slot::SUFFIX, steal, cold),
        ModifierTrait::new(modifier_slot::INSCRIPTION, steal, cold),
        ModifierTrait::new(modifier_slot::SUFFIX, steal, cold),
        ModifierTrait::new(modifier_slot::INSCRIPTION, steal, cold),
    ];
    for piece in base_slot::CHEST..base_slot::LAST + 1 {
        records.append(ModifierTrait::insignia(piece, fire, cold));
    }
    for _ in 0..5_u8 {
        records.append(ModifierTrait::new(modifier_slot::RUNE, fire, cold));
    }
    let mut parts = array![];
    let mut ids = array![];
    let mut next: u16 = 1;
    for record in records.span() {
        parts.append(*ModifierRecord::pack(record)[0]);
        ids.append(next);
        next += 1;
    }
    let mut worn = array![
        Worn { lane: 0, slot: base_slot::WEAPON, ids: [1, 2, 3, 0, 0], values: [5, 5, 5, 0, 0] },
        Worn { lane: 1, slot: base_slot::OFF_HAND, ids: [0, 4, 5, 0, 0], values: [0, 5, 5, 0, 0] },
    ];
    let mut k: u16 = 0;
    while k < 5 {
        let lane: u8 = (2 + k).try_into().unwrap();
        worn
            .append(
                Worn {
                    lane,
                    slot: base_slot::CHEST + lane - 2,
                    ids: [0, 0, 0, 6 + k, 11 + k],
                    values: [0, 0, 0, 7, 7],
                },
            );
        k += 1;
    }
    let loadout = Loadout {
        level: 20,
        profession: 1,
        points: array![].span(),
        bar_attributes: [0; 8],
        bar_attacks: 0,
        skills: [1, 2, 3, 4, 5, 6, 7, 8],
        elite_slot: 3,
        weapon: 0,
        weapon_damage: 0,
        weapon_ticks: 0,
        weapon_range: 0,
        damage_type: 0,
        weapon_attribute: 0,
        requirement_met: 0,
        personalised: true,
        strength_cap: 0,
        rating: 7,
        set_bonuses: 0,
        belt: [1, 8, 15, 22],
        belt_counts: [3, 3, 3, 3],
    };
    (loadout, worn.span(), ids.span(), parts.span())
}

// The library's words are the flattening's (D-168: `set_build` stores them, `enter` copies them).
#[test]
#[available_gas(l2_gas: 7554022)] // ceil(1.05 × 7194306 measured)
fn test_library_words_are_the_flattening() {
    let class = declare("FlattenLibrary").unwrap().contract_class();
    let library = IFlattenLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (loadout, worn, ids, records) = widest();
    let words = library.words(loadout, worn, ids, records);
    assert(words == SnapshotBuildTrait::words(@loadout, worn, ids, records), 'the flattening');
    let (stats, _, kit) = words;
    // Life steal 5 on five items; fire 7 on ten, less nothing; cold 7 × 15 against the heavy
    // class's 0, saturated at 0 below.
    assert(unpack_kit(kit).life_steal == 25, 'life steal');
    assert(unpack_stats(stats).level == 20, 'level');
}

// Cost: the library call of the widest equipment, the call alone (`get_available_gas` around it),
// the benchmark of `set_build`'s flattening.
#[test]
#[available_gas(l2_gas: 4631937)] // ceil(1.05 × 4411368 measured)
fn test_cost_library_call_widest() {
    let class = declare("FlattenLibrary").unwrap().contract_class();
    let library = IFlattenLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (loadout, worn, ids, records) = widest();
    let before = get_available_gas();
    let (stats, _, _) = library.words(loadout, worn, ids, records);
    let used = before - get_available_gas();
    println!("flatten library call, widest: {}", used);
    assert(stats != 0, 'words');
}

// Cost: the library call of a build without equipment (the fixed part).
#[test]
#[available_gas(l2_gas: 2065900)] // ceil(1.05 × 1967523 measured)
fn test_cost_library_call_empty() {
    let class = declare("FlattenLibrary").unwrap().contract_class();
    let library = IFlattenLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (loadout, _, _, _) = widest();
    let before = get_available_gas();
    let (stats, _, _) = library.words(loadout, array![].span(), array![].span(), array![].span());
    let used = before - get_available_gas();
    println!("flatten library call, empty: {}", used);
    assert(stats != 0, 'words');
}

// ---- design/20 §6 test 2: the extremal builds through the library (fix loop 1) -----------------

/// The attribute of the fixtures' ranks (a global id, D-157 A), the build's primary.
const PRIMARY: u8 = 13;

/// `records` as the registry stores them, one part each; their ids 1, 2, … in order.
fn registry(records: Span<Modifier>) -> (Span<u16>, Span<felt252>) {
    let mut ids = array![];
    let mut parts = array![];
    let mut next: u16 = 1;
    for record in records {
        parts.append(*ModifierRecord::pack(record)[0]);
        ids.append(next);
        next += 1;
    }
    (ids.span(), parts.span())
}

/// The sword (lane 0) holding modifiers 1–3 and the shield (lane 1) holding 4–5 in their held
/// slots (prefix, suffix, inscription; suffix, inscription), each rolled at `value`.
fn held_slots(value: u8) -> Array<Worn> {
    array![
        Worn {
            lane: 0,
            slot: base_slot::WEAPON,
            ids: [1, 2, 3, 0, 0],
            values: [value, value, value, 0, 0],
        },
        Worn {
            lane: 1,
            slot: base_slot::OFF_HAND,
            ids: [0, 4, 5, 0, 0],
            values: [0, value, value, 0, 0],
        },
    ]
}

/// The five held slots' records: one modifier of each held slot type holding `benefit`.
fn held_records(benefit: Passive) -> Array<Modifier> {
    let none: Passive = Default::default();
    array![
        ModifierTrait::new(modifier_slot::PREFIX, benefit, none),
        ModifierTrait::new(modifier_slot::SUFFIX, benefit, none),
        ModifierTrait::new(modifier_slot::INSCRIPTION, benefit, none),
        ModifierTrait::new(modifier_slot::SUFFIX, benefit, none),
        ModifierTrait::new(modifier_slot::INSCRIPTION, benefit, none),
    ]
}

/// A level-`level` build of `profession`, no attribute point, no weapon statistics, as
/// `Hub.set_build`'s `BuildTrait::loadout` makes it today.
fn bare(level: u8, profession: u8) -> Loadout {
    Loadout {
        level,
        profession,
        points: array![].span(),
        bar_attributes: [0; 8],
        bar_attacks: 0,
        skills: [0; 8],
        elite_slot: 255,
        weapon: 0,
        weapon_damage: 0,
        weapon_ticks: 0,
        weapon_range: 0,
        damage_type: 0,
        weapon_attribute: 0,
        requirement_met: 0,
        personalised: false,
        strength_cap: 0,
        rating: 0,
        set_bonuses: 0,
        belt: [0; 4],
        belt_counts: [0; 4],
    }
}

/// The library's words of the build, checked equal to the direct flattening's.
fn through_the_library(
    loadout: Loadout, worn: Span<Worn>, ids: Span<u16>, records: Span<felt252>,
) -> (felt252, felt252, felt252) {
    let class = declare("FlattenLibrary").unwrap().contract_class();
    let library = IFlattenLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let words = library.words(loadout, worn, ids, records);
    assert(words == SnapshotBuildTrait::words(@loadout, worn, ids, records), 'the flattening');
    words
}

// Max health: level 20, the sword's and the shield's five held slots at +30, insignias of 15 /
// 10 / 5 / 5 / 5 on the pieces (DS-23), five +50 health runes of distinct ids: 480 + 150 + 40 +
// 250 = 920. design/20's 1,020 adds two +50 set bonuses, which no item holds: armor sets are not
// laid out in the loadout (`set_bonuses` 0, `BuildTrait::loadout`).
#[test]
#[available_gas(l2_gas: 6732512)] // ceil(1.05 × 6411916 measured)
fn test_extremal_max_health_through_the_library() {
    let none: Passive = Default::default();
    let mut records = held_records(PassiveTrait::new(id::MAX_HEALTH, 0, 0, 0, 1, 30));
    let insignias = [15_i16, 10, 5, 5, 5];
    let mut piece = base_slot::CHEST;
    for value in insignias.span() {
        let benefit = PassiveTrait::new(id::MAX_HEALTH, 0, 0, 0, 1, *value);
        records.append(ModifierTrait::insignia(piece, benefit, none));
        piece += 1;
    }
    for _ in 0..5_u8 {
        let benefit = PassiveTrait::new(id::MAX_HEALTH, 0, 0, 0, 1, 50);
        records.append(ModifierTrait::new(modifier_slot::RUNE, benefit, none));
    }
    let (ids, parts) = registry(records.span());
    let mut worn = held_slots(30);
    let mut k: u16 = 0;
    while k < 5 {
        let lane: u8 = (2 + k).try_into().unwrap();
        let value: u8 = (*insignias.span()[k.into()]).try_into().unwrap();
        worn
            .append(
                Worn {
                    lane,
                    slot: base_slot::CHEST + lane - 2,
                    ids: [0, 0, 0, 6 + k, 11 + k],
                    values: [0, 0, 0, value, 50],
                },
            );
        k += 1;
    }
    let (stats, _, _) = through_the_library(bare(20, 1), worn.span(), ids, parts);
    assert(unpack_stats(stats).max_health == 920, 'max health 920');
}

// Max energy: an Arcanist at level 20 at Wellspring 15 (12 points and a +3 rune: DS-8) in light
// armor, the five held slots at +5: 30 + 45 + 20 + 25 = 120. design/20's 130 adds two +5 set
// bonuses, which no item holds (as above).
#[test]
#[available_gas(l2_gas: 3459547)] // ceil(1.05 × 3294806 measured)
fn test_extremal_max_energy_through_the_library() {
    let none: Passive = Default::default();
    let mut records = held_records(PassiveTrait::new(id::MAX_ENERGY, 0, 0, 0, 1, 5));
    let attribute = PassiveTrait::new(id::ATTRIBUTE, PRIMARY, 0, 0, 1, 3);
    records.append(ModifierTrait::new(modifier_slot::RUNE, attribute, none));
    let (ids, parts) = registry(records.span());
    let mut worn = held_slots(5);
    worn
        .append(
            Worn { lane: 2, slot: base_slot::CHEST, ids: [0, 0, 0, 0, 6], values: [0, 0, 0, 0, 3] },
        );
    let loadout = Loadout { points: array![(PRIMARY, 12)].span(), ..bare(20, 3) };
    let (stats, _, _) = through_the_library(loadout, worn.span(), ids, parts);
    let stats = unpack_stats(stats);
    assert(stats.max_energy == 120, 'max energy 120');
    assert(stats.primary_rank == 15, 'Wellspring 15');
}

// Weapon damage 32 (DS-4): a personalised maul at requirement 9, base damage 27: 27 × 1.2 rounded
// down. The loadout carries it; `set_build` cannot yet, since `BASE` lays out no weapon statistics
// (D-158): its loadout's weapon damage is 0.
#[test]
#[available_gas(l2_gas: 1531190)] // ceil(1.05 × 1458276 measured)
fn test_extremal_weapon_damage_through_the_library() {
    let loadout = Loadout {
        weapon_damage: 27, requirement_met: 1, personalised: true, ..bare(20, 1),
    };
    let (stats, _, _) = through_the_library(
        loadout, array![].span(), array![].span(), array![].span(),
    );
    assert(unpack_stats(stats).weapon_damage == 32, 'weapon damage 32');
}

// Ranks 15 (DS-8): 12 points and a +3 rune, on the primary and on every bar skill's attribute:
// every 4-bit rank of `MemberStats.ranks` at 15. `set_build` cannot yet: `Build.attributes` holds
// build-local indices and the global ids runes name are not numbered (D-157 A), so its loadout
// has no point.
#[test]
#[available_gas(l2_gas: 2135696)] // ceil(1.05 × 2033996 measured)
fn test_extremal_ranks_through_the_library() {
    let attribute = PassiveTrait::new(id::ATTRIBUTE, PRIMARY, 0, 0, 1, 3);
    let rune = ModifierTrait::new(modifier_slot::RUNE, attribute, Default::default());
    let (ids, parts) = registry(array![rune].span());
    let worn = array![
        Worn { lane: 2, slot: base_slot::CHEST, ids: [0, 0, 0, 0, 1], values: [0, 0, 0, 0, 3] },
    ];
    let loadout = Loadout {
        points: array![(PRIMARY, 12)].span(), bar_attributes: [PRIMARY; 8], ..bare(20, 1),
    };
    let (stats, _, _) = through_the_library(loadout, worn.span(), ids, parts);
    let stats = unpack_stats(stats);
    assert(stats.primary_rank == 15, 'primary 15');
    assert(stats.ranks == 0xffffffff, 'eight ranks of 15');
}
