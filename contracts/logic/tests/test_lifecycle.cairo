// ENG-06: the shared rules of the lifecycle: a tile of a chunk as a global position, the gate an
// adventurer can leave by, the hub's checks of a gate, the snapshot's base stats (design/03).
use grimworld_logic::content::exists;
use grimworld_logic::models::gate::{GateAssert, GateTrait, kind};
use grimworld_logic::models::location::{LocationTrait, kind as location_kind};
use grimworld_logic::packing::Lanes16;
use grimworld_logic::professions::ProfessionTrait;
use grimworld_logic::snapshot::{MemberBar, MemberKit, MemberStats, SnapshotTrait};

#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_position() {
    assert(LocationTrait::position(0, 0) == (0, 0), 'origin');
    assert(LocationTrait::position(0, 105) == (0, 7), 'row 7');
    assert(LocationTrait::position(16, 110) == (20, 22), 'chunk (1, 1)');
    assert(LocationTrait::position(112, 112) == (112, 112), 'the centre');
    assert(LocationTrait::position(224, 224) == (224, 224), 'the far corner');
}

#[test]
#[available_gas(l2_gas: 34608)] // ceil(1.05 × 32960 measured)
fn test_has_map() {
    let place = |kind: u8| {
        LocationTrait::new(
            kind, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, false, 0, 0, Lanes16 { lanes: [0; 15] },
        )
    };
    assert(
        !place(location_kind::TOWN).has_map() && !place(location_kind::OUTPOST).has_map(), 'hubs',
    );
    for kind in array![
        location_kind::ZONE, location_kind::DUNGEON, location_kind::ELITE, location_kind::RIFT,
        location_kind::TRIAL,
    ] {
        assert(place(kind).has_map(), 'an instance');
    }
    assert(!exists(array![0, 5].span()) && exists(array![1, 0].span()), 'exists: part 0');
}

// A gate is left from its source, on its anchor, when it is a hub gate or a link with no
// requirement.
#[test]
#[available_gas(l2_gas: 65195)] // ceil(1.05 × 62090 measured)
fn test_can_leave() {
    let gate = GateTrait::new(2, 1, 0, 105, 0, 0, kind::HUB, 0, 0);
    assert(gate.anchor() == (0, 7) && gate.entry() == (0, 0), 'anchor, entry');
    assert(gate.can_leave(2, 0, 7), 'on the anchor');
    assert(!gate.can_leave(3, 0, 7), 'another location');
    assert(!gate.can_leave(2, 1, 7) && !gate.can_leave(2, 0, 8), 'next to it');
    let link = GateTrait::new(2, 3, 0, 105, 112, 112, kind::LINK, 0, 0);
    assert(link.can_leave(2, 0, 7), 'a link');
    for refused in array![
        GateTrait::new(2, 3, 0, 105, 112, 112, kind::FLOOR, 0, 0),
        GateTrait::new(2, 3, 0, 105, 112, 112, kind::RIFT, 0, 0),
        GateTrait::new(2, 3, 0, 105, 112, 112, kind::LINK, 1, 0),
        GateTrait::new(2, 3, 0, 105, 112, 112, kind::LINK, 0, 4),
    ] {
        assert(!refused.can_leave(2, 0, 7), 'refused');
    }
}

#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_enterable() {
    GateTrait::new(1, 2, 0, 0, 0, 105, kind::HUB, 3, 0).assert_enterable(1, 3);
    GateTrait::new(1, 2, 0, 0, 0, 105, kind::LINK, 0, 0).assert_enterable(1, 0);
}

#[test]
#[should_panic(expected: 'gate: not in this hub')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_enterable_elsewhere() {
    GateTrait::new(1, 2, 0, 0, 0, 105, kind::HUB, 0, 0).assert_enterable(4, 0);
}

#[test]
#[should_panic(expected: 'gate: kind')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_enterable_floor() {
    GateTrait::new(1, 2, 0, 0, 0, 105, kind::FLOOR, 0, 0).assert_enterable(1, 0);
}

#[test]
#[should_panic(expected: 'gate: rank')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_enterable_rank() {
    GateTrait::new(1, 2, 0, 0, 0, 105, kind::HUB, 3, 0).assert_enterable(1, 2);
}

#[test]
#[should_panic(expected: 'gate: quest')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_enterable_quest() {
    GateTrait::new(1, 2, 0, 0, 0, 105, kind::HUB, 0, 5).assert_enterable(1, 9);
}

// design/03: health 100 + 20 per level above 1; energy, its pips and armor by profession.
#[test]
#[available_gas(l2_gas: 14406)] // ceil(1.05 × 13720 measured)
fn test_snapshot() {
    let snapshot = SnapshotTrait::new(
        20, 3, [1, 2, 3, 4, 5, 6, 7, 8], 2, [9, 10, 11, 12], [1, 2, 3, 4],
    );
    let stats = MemberStats {
        max_health: 480,
        max_energy: 30,
        energy_regen: 4,
        health_regen: 10,
        armor: 60,
        level: 20,
        profession: 3,
        ..Default::default(),
    };
    assert(snapshot.stats == stats, 'stats');
    assert(snapshot.bar == MemberBar { skills: [1, 2, 3, 4, 5, 6, 7, 8], elite_slot: 2 }, 'bar');
    assert(snapshot.kit == MemberKit { belt: [9, 10, 11, 12], ..Default::default() }, 'kit');
    assert(snapshot.belt_counts == [1, 2, 3, 4], 'belt');
    assert(
        (
            ProfessionTrait::energy(1), ProfessionTrait::energy_regen(1), ProfessionTrait::armor(1),
        ) == (20, 2, 80),
        'vanguard',
    );
    assert(
        (
            ProfessionTrait::energy(2), ProfessionTrait::energy_regen(2), ProfessionTrait::armor(2),
        ) == (25, 3, 70),
        'warden',
    );
}

#[test]
#[should_panic(expected: 'bad profession')]
#[available_gas(l2_gas: 16296)] // ceil(1.05 × 15520 measured)
fn test_snapshot_of_no_profession() {
    SnapshotTrait::new(1, 0, [0; 8], 255, [0; 4], [0; 4]);
}
