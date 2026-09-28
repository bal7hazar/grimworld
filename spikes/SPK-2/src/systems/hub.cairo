//! Hub actions of a typical day: accept a quest, claim it, enter an instance, leave it.

#[starknet::interface]
pub trait IHub<T> {
    fn accept_quest(ref self: T, adventurer: u32, quest: u32);
    fn claim_quest(ref self: T, adventurer: u32, quest: u32);
    /// Enters a location through a gate of the hub; returns the instance id.
    fn enter(ref self: T, adventurer: u32, location: u32) -> u32;
    /// Leaves the instance for the hub (returned).
    fn leave(ref self: T, adventurer: u32);
}

#[dojo::contract]
pub mod hub {
    use dojo::model::ModelStorage;
    use dojo::world::WorldStorage;
    use spk2::fate::fate;
    use spk2::models::{
        Adventurer, Balance, Counter, Instance, InstanceAdventurer, Location, Quest, QuestLog,
    };
    use starknet::get_caller_address;
    use super::IHub;

    fn owned(ref world: WorldStorage, id: u32) -> Adventurer {
        let adventurer: Adventurer = world.read_model(id);
        assert(adventurer.owner == get_caller_address().into(), 'not the owner');
        adventurer
    }

    #[abi(embed_v0)]
    impl HubImpl of IHub<ContractState> {
        fn accept_quest(ref self: ContractState, adventurer: u32, quest: u32) {
            let mut world = self.world(@"spk2");
            let owner = owned(ref world, adventurer);
            assert(owner.instance == 0, 'not in a hub');
            let registry: Quest = world.read_model(quest);
            assert(registry.hub == owner.hub, 'quest not here');
            assert(registry.level <= owner.level, 'level too low');
            let mut log: QuestLog = world.read_model((adventurer, quest));
            assert(log.status == 0, 'already accepted');
            log.status = 1;
            world.write_model(@log);
        }

        fn claim_quest(ref self: ContractState, adventurer: u32, quest: u32) {
            let mut world = self.world(@"spk2");
            let mut owner = owned(ref world, adventurer);
            assert(owner.instance == 0, 'not in a hub');
            let registry: Quest = world.read_model(quest);
            assert(registry.hub == owner.hub, 'quest not here');
            let mut log: QuestLog = world.read_model((adventurer, quest));
            assert(log.status == 1 && log.progress >= registry.target, 'not done');
            log.status = 2;
            owner.experience += registry.experience;
            owner.gold += registry.gold;
            let mut balance: Balance = world.read_model((adventurer, registry.item));
            balance.amount += 1;
            world.write_model(@log);
            world.write_model(@owner);
            world.write_model(@balance);
        }

        fn enter(ref self: ContractState, adventurer: u32, location: u32) -> u32 {
            let mut world = self.world(@"spk2");
            let mut owner = owned(ref world, adventurer);
            assert(owner.instance == 0, 'already in an instance');
            let gate: Location = world.read_model(location);
            assert(gate.hub == owner.hub, 'no gate here');
            assert(gate.level <= owner.level, 'level too low');
            // [Compute] A new instance, its entry draw, the adventurer's snapshot
            let mut counter: Counter = world.read_model('instance');
            counter.value += 1;
            let id = counter.value;
            let level: u16 = owner.level.into();
            world.write_model(@counter);
            world
                .write_model(
                    @Instance {
                        id, clock: 0, location, adventurer, goblins: 0, entry_draw: fate('entry'),
                    },
                );
            world
                .write_model(
                    @InstanceAdventurer {
                        instance_id: id,
                        adventurer,
                        x: gate.x,
                        y: gate.y,
                        facing: 0,
                        health: 100 + 20 * (level - 1),
                        max_health: 100 + 20 * (level - 1),
                        energy: 60,
                        max_energy: 75,
                        armor: 80,
                        strength: 60,
                        damage: 18,
                        regeneration: 2,
                        energy_regeneration: 3,
                        bleeding: 0,
                        poison: 0,
                        burning: 0,
                    },
                );
            owner.instance = id;
            world.write_model(@owner);
            id
        }

        fn leave(ref self: ContractState, adventurer: u32) {
            let mut world = self.world(@"spk2");
            let mut owner = owned(ref world, adventurer);
            let id = owner.instance;
            assert(id != 0, 'not in an instance');
            // [Write] Returned: the instance is closed and its state discarded
            let instance: Instance = world.read_model(id);
            let state: InstanceAdventurer = world.read_model((id, adventurer));
            world.erase_model(@instance);
            world.erase_model(@state);
            owner.instance = 0;
            world.write_model(@owner);
        }
    }
}
