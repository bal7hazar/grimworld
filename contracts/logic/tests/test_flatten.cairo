// CBT-02e (D-168): the snapshot's flattening as a library class. `FlattenLibrary.words` through a
// `library_call` is `BuildTrait::words` (WPN-01: the bar's and the belt's checks against their
// parts, the loadout, then `SnapshotBuildTrait::words`, whose unit tests are in
// `models/build.cairo`);
// here, what needs the declared class: the call's result and its cost on the widest equipment
// design/20 §1.2 counts (the benchmark of `Hub.set_build`'s flattening, D-158 (c)), and design/20
// §6 test 2's extremal builds as far as items and a loadout hold them (fix loop 1): the library's
// words equal the direct flattening's, the field its extremum; what the item model cannot hold yet
// is said at each test.
use core::testing::get_available_gas;
use grimworld_logic::interface::{IFlattenLibraryDispatcherTrait, IFlattenLibraryLibraryDispatcher};
use grimworld_logic::models::base::{Weapon, WeaponTrait, slot as base_slot};
use grimworld_logic::models::build::SnapshotBuildTrait;
use grimworld_logic::models::index::Modifier;
use grimworld_logic::models::item::{ItemRecord, ItemTrait, class};
use grimworld_logic::models::loadout::Loadout;
use grimworld_logic::models::member_kit::MemberKitTrait;
use grimworld_logic::models::member_stats::MemberStatsTrait;
use grimworld_logic::models::modifier::{ModifierRecord, ModifierTrait, slot as modifier_slot};
use grimworld_logic::models::sent_build::{Build, BuildTrait};
use grimworld_logic::models::skill::{SkillRecord, SkillTrait};
use grimworld_logic::models::worn::Worn;
use grimworld_logic::types::combat::{damage, skill_kind, weapon};
use grimworld_logic::types::passive::{Passive, PassiveTrait, id};
use snforge_std::{DeclareResultTrait, declare};
use starknet::storage_access::StorePacking;

#[generate_trait]
impl FixtureImpl of Fixture {
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
            Worn {
                lane: 0, slot: base_slot::WEAPON, ids: [1, 2, 3, 0, 0], values: [5, 5, 5, 0, 0],
            },
            Worn {
                lane: 1, slot: base_slot::OFF_HAND, ids: [0, 4, 5, 0, 0], values: [0, 5, 5, 0, 0],
            },
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

    /// The sword (lane 0) holding modifiers 1–3 and the shield (lane 1) holding 4–5 in their
    /// held slots (prefix, suffix, inscription; suffix, inscription), each rolled at `value`.
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

    /// What `Hub.set_build` sends the library for `loadout` (WPN-01): the build word of its bar
    /// and elite slot, each bar skill as its two `SKILL` parts (of the loadout's profession, its
    /// attribute and attack slot, the elite in its slot) and known, a potion's part for each
    /// distinct belt item, then the modifiers' `records`; its weapon packed, at requirement 0 when
    /// the loadout meets it, else 1. What the loadout holds that `set_build` cannot send (attribute
    /// points, a rating, a strength cap, set bonuses) is not sent.
    fn sent(loadout: @Loadout, records: Span<felt252>) -> Sent {
        let build = Build { bar: *loadout.skills, attributes: 0, elite_slot: *loadout.elite_slot };
        let mut parts: Array<felt252> = array![];
        let mut known: Array<bool> = array![];
        let mut slot: u8 = 0;
        let mut attacks: u8 = *loadout.bar_attacks;
        for skill in loadout.skills.span() {
            if *skill != 0 {
                let kind = if attacks % 2 == 1 {
                    skill_kind::ATTACK
                } else {
                    skill_kind::SKILL
                };
                let record = SkillTrait::new(
                    *loadout.profession,
                    *loadout.bar_attributes.span()[slot.into()],
                    kind,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    slot == *loadout.elite_slot,
                    [Default::default(); 3],
                )
                    .pack();
                parts.append(*record[0]);
                parts.append(*record[1]);
                known.append(true);
            }
            attacks /= 2;
            slot += 1;
        }
        let mut potions: u32 = 0;
        let belt = loadout.belt.span();
        for i in 0..4_u32 {
            let item = *belt[i];
            let mut first = item != 0;
            for j in 0..i {
                if *belt[j] == item {
                    first = false;
                }
            }
            if first {
                let potion = ItemTrait::new(class::POTION, 1, 0, 1, 0, Default::default(), 0, 0);
                parts.append(*potion.pack()[0]);
                potions += 1;
            }
        }
        for record in records {
            parts.append(*record);
        }
        let weapon = Weapon {
            class: *loadout.weapon,
            damage: *loadout.weapon_damage,
            ticks: *loadout.weapon_ticks,
            range: *loadout.weapon_range,
            damage_type: *loadout.damage_type,
            attribute: *loadout.weapon_attribute,
        };
        Sent {
            build,
            known: known.span(),
            parts: parts.span(),
            level: *loadout.level,
            profession: *loadout.profession,
            potions,
            weapon: weapon.pack(),
            requirement: if *loadout.requirement_met == 1 {
                0
            } else {
                1
            },
            personalised: *loadout.personalised,
            belt: *loadout.belt,
            counts: *loadout.belt_counts,
        }
    }

    /// The library's words of what `sent` sends, the items `worn` holding the modifiers `ids`.
    fn call(
        library: IFlattenLibraryLibraryDispatcher, sent: @Sent, worn: Span<Worn>, ids: Span<u16>,
    ) -> (felt252, felt252, felt252) {
        library
            .words(
                StorePacking::pack(*sent.build),
                *sent.known,
                *sent.parts,
                *sent.level,
                *sent.profession,
                0,
                *sent.potions,
                *sent.weapon,
                *sent.requirement,
                *sent.personalised,
                *sent.belt,
                *sent.counts,
                worn,
                ids,
            )
    }

    /// The library's words of the build, checked equal to the direct flattening of the loadout
    /// it builds from what it was sent (`BuildTrait::words`).
    fn through_the_library(
        loadout: Loadout, worn: Span<Worn>, ids: Span<u16>, records: Span<felt252>,
    ) -> (felt252, felt252, felt252) {
        let class = declare("FlattenLibrary").unwrap().contract_class();
        let library = IFlattenLibraryLibraryDispatcher { class_hash: *class.class_hash };
        let sent = Self::sent(@loadout, records);
        let words = Self::call(library, @sent, worn, ids);
        let built = sent
            .build
            .loadout(
                sent.level,
                sent.profession,
                sent.build.bar_kinds(sent.parts),
                WeaponTrait::unpack(sent.weapon),
                sent.requirement,
                sent.personalised,
                sent.belt,
                sent.counts,
            );
        assert(words == SnapshotBuildTrait::words(@built, worn, ids, records), 'the flattening');
        words
    }
}

/// What `Hub.set_build` sends `FlattenLibrary.words` (`Fixture::sent`).
#[derive(Drop)]
struct Sent {
    build: Build,
    known: Span<bool>,
    parts: Span<felt252>,
    level: u8,
    profession: u8,
    potions: u32,
    weapon: u128,
    requirement: u8,
    personalised: bool,
    belt: [u32; 4],
    counts: [u8; 4],
}

// The library's words are the flattening's (D-168: `set_build` stores them, `enter` copies them).
#[test]
// gas: raised, WPN-01: the library checks the bar and the belt against their parts and builds the loadout (D-310)
#[available_gas(l2_gas: 16494003)] // ceil(1.05 × 15708574 measured)
fn test_library_words_are_the_flattening() {
    let class = declare("FlattenLibrary").unwrap().contract_class();
    let library = IFlattenLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (loadout, worn, ids, records) = Fixture::widest();
    let words = Fixture::through_the_library(loadout, worn, ids, records);
    assert(words == Fixture::call(library, @Fixture::sent(@loadout, records), worn, ids), 'again');
    let (stats, _, kit) = words;
    // Life steal 5 on five items; fire 7 on ten, less nothing; cold 7 × 15 against the heavy
    // class's 0, saturated at 0 below.
    assert(MemberKitTrait::unpack(kit).life_steal == 25, 'life steal');
    assert(MemberStatsTrait::unpack(stats).level == 20, 'level');
}

// Cost: the library call of the widest equipment, the call alone (`get_available_gas` around it),
// the benchmark of `set_build`'s flattening.
#[test]
// gas: raised, WPN-01: the library checks the bar and the belt against their parts and builds the loadout (D-310)
#[available_gas(l2_gas: 7293214)] // ceil(1.05 × 6945918 measured)
fn test_cost_library_call_widest() {
    let class = declare("FlattenLibrary").unwrap().contract_class();
    let library = IFlattenLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (loadout, worn, ids, records) = Fixture::widest();
    let sent = Fixture::sent(@loadout, records);
    let before = get_available_gas();
    let (stats, _, _) = Fixture::call(library, @sent, worn, ids);
    let used = before - get_available_gas();
    println!("flatten library call, widest: {}", used);
    assert(stats != 0, 'words');
}

// Cost: the library call of a build without equipment (the fixed part).
#[test]
// gas: raised, WPN-01: the library checks the bar and the belt against their parts and builds the loadout (D-310)
#[available_gas(l2_gas: 4677523)] // ceil(1.05 × 4454783 measured)
fn test_cost_library_call_empty() {
    let class = declare("FlattenLibrary").unwrap().contract_class();
    let library = IFlattenLibraryLibraryDispatcher { class_hash: *class.class_hash };
    let (loadout, _, _, _) = Fixture::widest();
    let sent = Fixture::sent(@loadout, array![].span());
    let before = get_available_gas();
    let (stats, _, _) = Fixture::call(library, @sent, array![].span(), array![].span());
    let used = before - get_available_gas();
    println!("flatten library call, empty: {}", used);
    assert(stats != 0, 'words');
}

// ---- design/20 §6 test 2: the extremal builds through the library (fix loop 1) -----------------

/// The attribute of the fixtures' ranks (a global id, D-157 A), the build's primary.
const PRIMARY: u8 = 13;

// Max health: level 20, the sword's and the shield's five held slots at +30, insignias of 15 /
// 10 / 5 / 5 / 5 on the pieces (DS-23), five +50 health runes of distinct ids: 480 + 150 + 40 +
// 250 = 920. design/20's 1,020 adds two +50 set bonuses, which no item holds: armor sets are not
// laid out in the loadout (`set_bonuses` 0, `BuildTrait::loadout`).
#[test]
// gas: raised, WPN-01: the library checks the bar and the belt against their parts and builds the loadout (D-310)
#[available_gas(l2_gas: 7299995)] // ceil(1.05 × 6952376 measured)
fn test_extremal_max_health_through_the_library() {
    let none: Passive = Default::default();
    let mut records = Fixture::held_records(PassiveTrait::new(id::MAX_HEALTH, 0, 0, 0, 1, 30));
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
    let (ids, parts) = Fixture::registry(records.span());
    let mut worn = Fixture::held_slots(30);
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
    let (stats, _, _) = Fixture::through_the_library(Fixture::bare(20, 1), worn.span(), ids, parts);
    assert(MemberStatsTrait::unpack(stats).max_health == 920, 'max health 920');
}

// Max energy: an Arcanist at level 20 at Wellspring 15 (12 points and a +3 rune: DS-8) in light
// armor, the five held slots at +5: 30 + 45 + 20 + 25 = 120. design/20's 130 adds two +5 set
// bonuses, which no item holds (as above). Flattened directly: no input of `set_build` carries
// attribute points yet (D-157 A), so the library is never sent them.
#[test]
#[available_gas(l2_gas: 3459547)] // ceil(1.05 × 3294806 measured)
fn test_extremal_max_energy_flattened() {
    let none: Passive = Default::default();
    let mut records = Fixture::held_records(PassiveTrait::new(id::MAX_ENERGY, 0, 0, 0, 1, 5));
    let attribute = PassiveTrait::new(id::ATTRIBUTE, PRIMARY, 0, 0, 1, 3);
    records.append(ModifierTrait::new(modifier_slot::RUNE, attribute, none));
    let (ids, parts) = Fixture::registry(records.span());
    let mut worn = Fixture::held_slots(5);
    worn
        .append(
            Worn { lane: 2, slot: base_slot::CHEST, ids: [0, 0, 0, 0, 6], values: [0, 0, 0, 0, 3] },
        );
    let loadout = Loadout { points: array![(PRIMARY, 12)].span(), ..Fixture::bare(20, 3) };
    let (stats, _, _) = SnapshotBuildTrait::words(@loadout, worn.span(), ids, parts);
    let stats = MemberStatsTrait::unpack(stats);
    assert(stats.max_energy == 120, 'max energy 120');
    assert(stats.primary_rank == 15, 'Wellspring 15');
}

// Weapon damage 32 (DS-4): a personalised maul at requirement 9, base damage 27: 27 × 1.2 rounded
// down, its requirement met. `set_build` sends it as the worn item's weapon (WPN-01, D-158).
#[test]
// gas: raised, WPN-01: the library checks the bar and the belt against their parts and builds the loadout (D-310)
#[available_gas(l2_gas: 2055046)] // ceil(1.05 × 1957186 measured)
fn test_extremal_weapon_damage_through_the_library() {
    let loadout = Loadout {
        weapon: weapon::MAUL,
        weapon_damage: 27,
        requirement_met: 1,
        personalised: true,
        ..Fixture::bare(20, 1),
    };
    let (stats, _, _) = Fixture::through_the_library(
        loadout, array![].span(), array![].span(), array![].span(),
    );
    assert(MemberStatsTrait::unpack(stats).weapon_damage == 32, 'weapon damage 32');
}

// Ranks 15 (DS-8): 12 points and a +3 rune, on the primary and on every bar skill's attribute:
// every 4-bit rank of `MemberStats.ranks` at 15. `set_build` cannot yet: `Build.attributes` holds
// build-local indices and the global ids runes name are not numbered (D-157 A), so its loadout
// has no point: flattened directly, as above.
#[test]
#[available_gas(l2_gas: 2135696)] // ceil(1.05 × 2033996 measured)
fn test_extremal_ranks_flattened() {
    let attribute = PassiveTrait::new(id::ATTRIBUTE, PRIMARY, 0, 0, 1, 3);
    let rune = ModifierTrait::new(modifier_slot::RUNE, attribute, Default::default());
    let (ids, parts) = Fixture::registry(array![rune].span());
    let worn = array![
        Worn { lane: 2, slot: base_slot::CHEST, ids: [0, 0, 0, 0, 1], values: [0, 0, 0, 0, 3] },
    ];
    let loadout = Loadout {
        points: array![(PRIMARY, 12)].span(), bar_attributes: [PRIMARY; 8], ..Fixture::bare(20, 1),
    };
    let (stats, _, _) = SnapshotBuildTrait::words(@loadout, worn.span(), ids, parts);
    let stats = MemberStatsTrait::unpack(stats);
    assert(stats.primary_rank == 15, 'primary 15');
    assert(stats.ranks == 0xffffffff, 'eight ranks of 15');
}
