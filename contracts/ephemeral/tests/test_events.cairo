// The events of `Instances` have the keys and data of docs/architecture/ENG-01-interfaces.md: the
// selector of the name, then the instance id; the data in the declared order.
use grimworld_ephemeral::events::{BatchPlayed, InstanceClosed, InstanceEntered, Refused};
use grimworld_ephemeral::systems::instances::Instances::Event;
use grimworld_logic::types::{Outcome, Refusal, Stop, instance_id};

fn split(event: Event) -> (Array<felt252>, Array<felt252>) {
    let mut keys = array![];
    let mut data = array![];
    starknet::Event::append_keys_and_data(@event, ref keys, ref data);
    (keys, data)
}

#[test]
#[available_gas(l2_gas: 92547)] // ceil(1.05 × 88140 measured)
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
            },
        ),
    );
    assert(keys == array![selector!("BatchPlayed"), id.into()], 'batch keys');
    // Stop::Invalid is variant 2.
    assert(data == array![9, 40, 3, 2, 43, 77], 'batch data');

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

    let (keys, data) = split(
        Event::InstanceClosed(InstanceClosed { instance_id: id, outcome: Outcome::Defeated }),
    );
    assert(keys == array![selector!("InstanceClosed"), id.into()], 'closed keys');
    assert(data == array![2], 'closed data');
}
