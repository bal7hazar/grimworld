//! The heaviest ordinary action: a weapon attack (tick cost 1) followed by one world tick with
//! 8 awake goblins and the shared flood.

#[starknet::interface]
pub trait ITickWorstCase<T> {
    /// The adventurer of the instance attacks the adjacent goblin `target`, then one tick runs.
    /// Goblins are one model each.
    fn attack(ref self: T, instance_id: u32, target: u32);
    /// The same action with the 8 goblins in one model, one felt each (`Pack`): the storage
    /// lever, measured.
    fn attack_packed(ref self: T, instance_id: u32, target: u32);
}

#[dojo::contract]
pub mod tick_worst_case {
    use dojo::model::ModelStorage;
    use dojo::world::WorldStorage;
    use spk2::models::{
        Goblin, Instance, InstanceAdventurer, Pack, Window, pack_goblin, unpack_goblin,
    };
    use spk2::rules::{attack, origin_key, window_origin, world_tick};
    use super::ITickWorstCase;

    /// The action and the tick on goblins in memory, whatever their storage.
    fn act(
        ref world: WorldStorage,
        ref instance: Instance,
        ref adventurer: InstanceAdventurer,
        goblins: Array<Goblin>,
        target: u32,
    ) -> Array<Goblin> {
        let (x, y, _) = window_origin(adventurer.x, adventurer.y);
        let window: Window = world.read_model((instance.id, origin_key(x, y)));
        // [Compute] The action
        let mut attacked: Array<Goblin> = array![];
        for goblin in goblins {
            let mut goblin = goblin;
            if goblin.id == target {
                attack(ref adventurer, ref goblin);
            }
            attacked.append(goblin);
        }
        // [Compute] One world tick
        let (goblins, _) = world_tick(
            ref adventurer, attacked.span(), window.terrain, instance.clock,
        );
        instance.clock += 1;
        goblins
    }

    #[abi(embed_v0)]
    impl TickWorstCaseImpl of ITickWorstCase<ContractState> {
        fn attack(ref self: ContractState, instance_id: u32, target: u32) {
            let mut world = self.world(@"spk2");
            // [Read] Instance, adventurer, goblins, window (stand-in for the assembly)
            let mut instance: Instance = world.read_model(instance_id);
            let mut adventurer: InstanceAdventurer = world
                .read_model((instance_id, instance.adventurer));
            assert(adventurer.health != 0, 'adventurer defeated');
            let mut keys: Array<(u32, u32)> = array![];
            let mut id: u32 = 1;
            while id <= instance.goblins.into() {
                keys.append((instance_id, id));
                id += 1;
            }
            let goblins: Array<Goblin> = world.read_models(keys.span());
            let goblins = act(ref world, ref instance, ref adventurer, goblins, target);
            // [Write] One write per model
            world.write_model(@instance);
            world.write_model(@adventurer);
            let mut refs: Array<@Goblin> = array![];
            for goblin in goblins.span() {
                refs.append(goblin);
            }
            world.write_models(refs.span());
        }

        fn attack_packed(ref self: ContractState, instance_id: u32, target: u32) {
            let mut world = self.world(@"spk2");
            let mut instance: Instance = world.read_model(instance_id);
            let mut adventurer: InstanceAdventurer = world
                .read_model((instance_id, instance.adventurer));
            assert(adventurer.health != 0, 'adventurer defeated');
            let pack: Pack = world.read_model(instance_id);
            let mut goblins: Array<Goblin> = array![];
            let mut id: u32 = 1;
            for packed in pack.goblins.span() {
                goblins.append(unpack_goblin(instance_id, id, *packed));
                id += 1;
            }
            let goblins = act(ref world, ref instance, ref adventurer, goblins, target);
            let s: Span<Goblin> = goblins.span();
            let packed: [felt252; 8] = [
                pack_goblin(s[0]), pack_goblin(s[1]), pack_goblin(s[2]), pack_goblin(s[3]),
                pack_goblin(s[4]), pack_goblin(s[5]), pack_goblin(s[6]), pack_goblin(s[7]),
            ];
            world.write_model(@instance);
            world.write_model(@adventurer);
            world.write_model(@Pack { instance_id, goblins: packed });
        }
    }
}
