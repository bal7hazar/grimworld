//! A queue of moves in one transaction (design/02 *Action batching*): each move is followed by
//! one tick, and the queue stops when the player would want to react.

#[starknet::interface]
pub trait IQueueMoves<T> {
    /// Moves the adventurer of the instance, one tile per direction (East, NorthEast, NorthWest,
    /// West, SouthWest, SouthEast), at most 10.
    /// # Returns
    /// * The number of moves done
    fn walk(ref self: T, instance_id: u32, moves: Array<u8>) -> u8;
}

#[dojo::contract]
pub mod queue_moves {
    use dojo::model::ModelStorage;
    use spk2::board::{bitwise, has};
    use spk2::models::{Goblin, Instance, InstanceAdventurer, Window};
    use spk2::rules::{in_sight, neighbour, origin_key, window_origin, world_tick};
    use spk2::tables::WIDTH;
    use super::IQueueMoves;

    /// Longest queue (design/02: a cap set by measurement; 10 is the brief's worst case).
    pub const MAX_QUEUE: u32 = 10;

    /// Whether a goblin alive stands on a tile.
    fn occupied(goblins: Span<Goblin>, x: u8, y: u8) -> bool {
        for goblin in goblins {
            if *goblin.health != 0 && *goblin.x == x && *goblin.y == y {
                return true;
            }
        }
        false
    }

    #[abi(embed_v0)]
    impl QueueMovesImpl of IQueueMoves<ContractState> {
        fn walk(ref self: ContractState, instance_id: u32, moves: Array<u8>) -> u8 {
            assert(moves.len() <= MAX_QUEUE, 'queue too long');
            let mut world = self.world(@"spk2");
            // [Read] Instance, adventurer, goblins, the current window
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
            let mut goblins: Array<Goblin> = world.read_models(keys.span());
            let (x, y, _) = window_origin(adventurer.x, adventurer.y);
            let mut window: Window = world.read_model((instance_id, origin_key(x, y)));
            let mut seen = in_sight(@adventurer, goblins.span());
            let mut done: u8 = 0;
            for direction in moves {
                // [Check] An invalid move drops the rest of the queue, without reverting
                let (nx, ny) = neighbour(adventurer.x, adventurer.y, direction);
                let (ox, oy, _) = window_origin(adventurer.x, adventurer.y);
                let tile = (ny - oy) * WIDTH + (nx - ox);
                if !has(window.terrain.into(), tile) || occupied(goblins.span(), nx, ny) {
                    break;
                }
                // [Compute] The move, then one tick on the window that followed
                adventurer.x = nx;
                adventurer.y = ny;
                adventurer.facing = direction;
                let (ox, oy, _) = window_origin(nx, ny);
                window = world.read_model((instance_id, origin_key(ox, oy)));
                let (next, hit) = world_tick(
                    ref adventurer, goblins.span(), window.terrain, instance.clock,
                );
                goblins = next;
                instance.clock += 1;
                done += 1;
                // [Check] Stop conditions: hit by a goblin, a goblin entered sight, defeat.
                // Chunk reveal, loot and alerts do not exist in this spike.
                let now = in_sight(@adventurer, goblins.span());
                let (_, changed, _) = bitwise(seen.into(), now.into());
                let (entered, _, _) = bitwise(changed, now.into());
                seen = now;
                if hit || entered != 0 || adventurer.health == 0 {
                    break;
                }
            }
            // [Write] One write per model
            world.write_model(@instance);
            world.write_model(@adventurer);
            let mut refs: Array<@Goblin> = array![];
            for goblin in goblins.span() {
                refs.append(goblin);
            }
            world.write_models(refs.span());
            done
        }
    }
}
