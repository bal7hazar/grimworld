//! Writes the measured states (not measured itself).

#[starknet::interface]
pub trait ISetup<T> {
    /// The worst-case tick on an instance: goblin models and their packed copy.
    fn worst_case(ref self: T, instance_id: u32);
    /// The queue on an instance with its first `goblins` goblins (8: the worst case, 0: plain
    /// exploration), and the windows along its 10 moves.
    fn queue(ref self: T, instance_id: u32, goblins: u8);
    /// An adversarial tick (fixtures::MAZE, SEALED or DEEP), as `worst_case`.
    fn board(ref self: T, instance_id: u32);
    /// The expensive valid queue on the serpentine (fixtures::SERPENT), as `queue`.
    fn serpent(ref self: T, instance_id: u32);
    /// Adventurers 1 (signed) and 2 (unsigned) in hub 1, the Region 1 book, ingredients.
    fn alchemy(ref self: T);
    /// Adventurer 3 in hub 1, quests 1 (to accept) and 2 (done, to claim), location 10.
    fn hub(ref self: T);
}

#[dojo::contract]
pub mod setup {
    use dojo::model::ModelStorage;
    use spk2::alchemy::{
        REGION_1_MASKS, REGION_1_PAIRS, REGION_1_RARITIES, REGION_1_RECIPES, REGION_1_REMAINING,
    };
    use spk2::fixtures::{
        COMB, PILLARS, QUEUE_LENGTH, SERPENTINE, START_X, START_Y, adventurer, board, queue_goblins,
        serpent_goblins, window, worst_goblins,
    };
    use spk2::models::{
        Adventurer, Balance, Book, Counter, Goblin, Grimoire, Instance, Location, Pack, Quest,
        QuestLog, Window, pack_goblin,
    };
    use spk2::rules::{origin_key, window_origin};
    use starknet::get_caller_address;
    use super::ISetup;

    pub const HUB: u32 = 1;
    pub const BOOK: u32 = 1;
    pub const INGREDIENT: u32 = 100;
    pub const POTION: u32 = 200;
    pub const FAILED: u32 = 300;
    pub const LOCATION: u32 = 10;

    fn hub_adventurer(id: u32) -> Adventurer {
        Adventurer {
            id,
            owner: get_caller_address().into(),
            level: 20,
            experience: 1000,
            gold: 50,
            hub: HUB,
            instance: 0,
        }
    }

    /// An instance for one tick: goblin models, their packed copy (when 8), one window.
    fn write_tick(
        ref self: ContractState, instance_id: u32, goblins: Array<Goblin>, terrain: felt252,
    ) {
        let mut world = self.world(@"spk2");
        world
            .write_model(
                @Instance {
                    id: instance_id,
                    clock: 0,
                    location: LOCATION,
                    adventurer: 1,
                    goblins: goblins.len().try_into().unwrap(),
                    entry_draw: 0,
                },
            );
        world.write_model(@adventurer(instance_id, 1, true));
        let mut packed: Array<felt252> = array![];
        for goblin in goblins.span() {
            world.write_model(goblin);
            packed.append(pack_goblin(goblin));
        }
        let p = packed.span();
        if p.len() == 8 {
            world
                .write_model(
                    @Pack {
                        instance_id,
                        goblins: [*p[0], *p[1], *p[2], *p[3], *p[4], *p[5], *p[6], *p[7]],
                    },
                );
        }
        let (x, y, _) = window_origin(START_X, START_Y);
        world.write_model(@Window { instance_id, origin: origin_key(x, y), terrain });
    }

    /// An instance for a queue: goblin models and the windows along its 10 moves.
    fn write_queue(ref self: ContractState, instance_id: u32, goblins: Array<Goblin>, kind: u8) {
        let mut world = self.world(@"spk2");
        world
            .write_model(
                @Instance {
                    id: instance_id,
                    clock: 0,
                    location: LOCATION,
                    adventurer: 1,
                    goblins: goblins.len().try_into().unwrap(),
                    entry_draw: 0,
                },
            );
        world.write_model(@adventurer(instance_id, 1, false));
        for goblin in goblins.span() {
            world.write_model(goblin);
        }
        let (x, y, _) = window_origin(START_X, START_Y);
        let mut step: u8 = 0;
        while step <= QUEUE_LENGTH {
            world
                .write_model(
                    @Window {
                        instance_id,
                        origin: origin_key(x + step, y),
                        terrain: window(kind, x + step, y),
                    },
                );
            step += 1;
        }
    }

    #[abi(embed_v0)]
    impl SetupImpl of ISetup<ContractState> {
        fn worst_case(ref self: ContractState, instance_id: u32) {
            let (x, y, _) = window_origin(START_X, START_Y);
            write_tick(ref self, instance_id, worst_goblins(instance_id), window(COMB, x, y));
        }

        fn board(ref self: ContractState, instance_id: u32) {
            let (terrain, goblins) = board(instance_id);
            write_tick(ref self, instance_id, goblins, terrain);
        }

        fn serpent(ref self: ContractState, instance_id: u32) {
            write_queue(ref self, instance_id, serpent_goblins(instance_id), SERPENTINE);
        }

        fn queue(ref self: ContractState, instance_id: u32, goblins: u8) {
            let mut kept: Array<Goblin> = array![];
            for goblin in queue_goblins(instance_id) {
                if goblin.id <= goblins.into() {
                    kept.append(goblin);
                }
            }
            write_queue(ref self, instance_id, kept, PILLARS);
        }

        fn alchemy(ref self: ContractState) {
            let mut world = self.world(@"spk2");
            world
                .write_model(
                    @Book {
                        id: BOOK,
                        ingredients: 10,
                        rarities: REGION_1_RARITIES,
                        masks: REGION_1_MASKS,
                        recipes: REGION_1_RECIPES,
                        ingredient: INGREDIENT,
                        potion: POTION,
                        failed: FAILED,
                    },
                );
            // Adventurer 1 brews with signatures, adventurer 2 without
            world.write_model(@hub_adventurer(1));
            world.write_model(@hub_adventurer(2));
            world
                .write_model(
                    @Grimoire {
                        adventurer: 1, book: BOOK, known: 0, remaining: REGION_1_REMAINING,
                    },
                );
            world
                .write_model(
                    @Grimoire { adventurer: 2, book: BOOK, known: 0, remaining: REGION_1_PAIRS },
                );
            let mut item: u32 = 0;
            while item != 10 {
                world.write_model(@Balance { owner: 1, item: INGREDIENT + item, amount: 10 });
                world.write_model(@Balance { owner: 2, item: INGREDIENT + item, amount: 10 });
                item += 1;
            }
        }

        fn hub(ref self: ContractState) {
            let mut world = self.world(@"spk2");
            world.write_model(@hub_adventurer(3));
            world
                .write_model(
                    @Quest {
                        id: 1, hub: HUB, level: 1, target: 10, experience: 500, gold: 20, item: 400,
                    },
                );
            world
                .write_model(
                    @Quest {
                        id: 2, hub: HUB, level: 1, target: 10, experience: 500, gold: 20, item: 400,
                    },
                );
            world.write_model(@QuestLog { adventurer: 3, quest: 2, status: 1, progress: 10 });
            world
                .write_model(
                    @Location { id: LOCATION, hub: HUB, level: 1, x: START_X, y: START_Y },
                );
            // Instances entered from the hub start after the fixtures' ids
            world.write_model(@Counter { id: 'instance', value: 100 });
        }
    }
}
