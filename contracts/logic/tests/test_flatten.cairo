// CBT-02e (D-168): the snapshot's flattening as a library class. `FlattenLibrary.words` through a
// `library_call` is `SnapshotBuildTrait::words`, whose unit tests are in `snapshot.cairo`; here,
// what needs the declared class: the call's result and its cost on the widest equipment design/20
// §1.2 counts (the benchmark of `Hub.set_build`'s flattening, D-158 (c)).
use core::testing::get_available_gas;
use grimworld_logic::interface::{IFlattenLibraryDispatcherTrait, IFlattenLibraryLibraryDispatcher};
use grimworld_logic::models::base::slot as base_slot;
use grimworld_logic::models::index::Modifier;
use grimworld_logic::models::modifier::{ModifierRecord, ModifierTrait, slot as modifier_slot};
use grimworld_logic::snapshot::{Loadout, SnapshotBuildTrait, Worn, unpack_kit, unpack_stats};
use grimworld_logic::types::combat::damage;
use grimworld_logic::types::passive::{PassiveTrait, id};
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
#[available_gas(l2_gas: 7562663)] // ceil(1.05 × 7202536 measured)
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
#[available_gas(l2_gas: 4640683)] // ceil(1.05 × 4419698 measured)
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
#[available_gas(l2_gas: 2074646)] // ceil(1.05 × 1975853 measured)
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
