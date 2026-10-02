// The events of `Instances` have the keys and data of docs/architecture/ENG-01-interfaces.md: the
// selector of the name, then the instance id; the data in the declared order.
use grimworld_ephemeral::events::{
    BatchPlayed, ChunkRevealed, Defeated, GoblinKilled, InstanceClosed, InstanceEntered, Refused,
};
use grimworld_ephemeral::systems::instances::Instances::Event;
use grimworld_logic::types::{Outcome, Refusal, Stop, instance_id};

fn split(event: Event) -> (Array<felt252>, Array<felt252>) {
    let mut keys = array![];
    let mut data = array![];
    starknet::Event::append_keys_and_data(@event, ref keys, ref data);
    (keys, data)
}

#[test]
// gas: raised, pins Stop::Version, Refusal::Version and their ordinals (F-15)
#[available_gas(l2_gas: 207071)] // ceil(1.05 × 197210 measured)
fn test_instances_event_keys_and_data() {
    let id = instance_id(5, 2);
    let (keys, data) = split(
        Event::InstanceEntered(
            InstanceEntered { instance_id: id, adventurer_id: 9, location: 3, gate: 4 },
        ),
    );
    assert(keys == array![selector!("InstanceEntered"), id.into()], 'entered keys');
    assert(data == array![9, 3, 4], 'entered data');

    let (keys, data) = split(
        Event::BatchPlayed(
            BatchPlayed {
                instance_id: id,
                adventurer_id: 9,
                from: 40,
                played: 3,
                stop: Stop::Invalid,
                sequence: 43,
                clock: 77,
                version: 6,
            },
        ),
    );
    assert(keys == array![selector!("BatchPlayed"), id.into()], 'batch keys');
    // Stop::Invalid is variant 2.
    assert(data == array![9, 40, 3, 2, 43, 77, 6], 'batch data');

    // A batch refused for its content version (D-141, E-5): nothing ran, so `played` is 0, `from`
    // and `sequence` are the instance's, and `version` is the registry's current one (7), not the
    // 6 the client sent. `Stop::Version` is variant 6.
    let (_, data) = split(
        Event::BatchPlayed(
            BatchPlayed {
                instance_id: id,
                adventurer_id: 9,
                from: 40,
                played: 0,
                stop: Stop::Version,
                sequence: 40,
                clock: 77,
                version: 7,
            },
        ),
    );
    assert(data == array![9, 40, 0, 6, 40, 77, 7], 'version stop data');

    // The ordinals 0 to 5 are unchanged; Version was appended.
    let mut stops = array![];
    for stop in array![
        Stop::None, Stop::Sequence, Stop::Invalid, Stop::Weight, Stop::Defeated, Stop::Closed,
        Stop::Version,
    ] {
        Serde::serialize(@stop, ref stops);
    }
    assert(stops == array![0, 1, 2, 3, 4, 5, 6], 'stop ordinals');

    let (keys, data) = split(
        Event::Refused(
            Refused {
                instance_id: id, adventurer_id: 9, from: 40, sequence: 41, reason: Refusal::Gone,
            },
        ),
    );
    assert(keys == array![selector!("Refused"), id.into()], 'refused keys');
    // Refusal::Gone is variant 4.
    assert(data == array![9, 40, 41, 4], 'refused data');

    // An `open`, `mine` or `barter` computed under another content version (D-141):
    // Refusal::Version is variant 8, appended after Price (7).
    let (_, data) = split(
        Event::Refused(
            Refused {
                instance_id: id, adventurer_id: 9, from: 40, sequence: 40, reason: Refusal::Version,
            },
        ),
    );
    assert(data == array![9, 40, 40, 8], 'version refusal data');

    // The ordinals 0 to 7 are unchanged; Version was appended.
    let mut reasons = array![];
    for reason in array![
        Refusal::Sequence, Refusal::Closed, Refusal::Absent, Refusal::Reach, Refusal::Gone,
        Refusal::Gate, Refusal::Sealed, Refusal::Price, Refusal::Version,
    ] {
        Serde::serialize(@reason, ref reasons);
    }
    assert(reasons == array![0, 1, 2, 3, 4, 5, 6, 7, 8], 'refusal ordinals');

    let (keys, data) = split(
        Event::InstanceClosed(InstanceClosed { instance_id: id, outcome: Outcome::Defeated }),
    );
    assert(keys == array![selector!("InstanceClosed"), id.into()], 'closed keys');
    assert(data == array![2], 'closed data');
}

// Fix loop 1, F-7: the per-action events of design/02 beside BatchPlayed.
#[test]
#[available_gas(l2_gas: 53834)] // ceil(1.05 × 51270 measured)
fn test_per_action_event_keys_and_data() {
    let id = instance_id(5, 2);
    let (keys, data) = split(
        Event::GoblinKilled(
            GoblinKilled { instance_id: id, entity: 42, caste: 3, tile: 0x0707, by: 0 },
        ),
    );
    assert(keys == array![selector!("GoblinKilled"), id.into()], 'killed keys');
    assert(data == array![42, 3, 0x0707, 0], 'killed data');

    let (keys, data) = split(Event::ChunkRevealed(ChunkRevealed { instance_id: id, chunk: 112 }));
    assert(keys == array![selector!("ChunkRevealed"), id.into()], 'revealed keys');
    assert(data == array![112], 'revealed data');

    let (keys, data) = split(Event::Defeated(Defeated { instance_id: id, adventurer_id: 9 }));
    assert(keys == array![selector!("Defeated"), id.into()], 'defeated keys');
    assert(data == array![9], 'defeated data');
}
