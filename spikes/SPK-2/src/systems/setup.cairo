//! Writes the measured states (not measured itself).

#[starknet::interface]
pub trait ISetup<T> {
    /// Instance 1: the worst-case tick.
    fn worst_case(ref self: T);
    /// Instance 2: the queue of 10 moves, and the windows along it.
    fn queue(ref self: T);
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
        COMB, PILLARS, QUEUE, QUEUE_LENGTH, START_X, START_Y, WORST, adventurer, queue_goblins,
        window, worst_goblins,
    };
    use spk2::models::{
        Adventurer, Balance, Book, Counter, Grimoire, Instance, Location, Quest, QuestLog, Window,
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

    #[abi(embed_v0)]
    impl SetupImpl of ISetup<ContractState> {
        fn worst_case(ref self: ContractState) {
            let mut world = self.world(@"spk2");
            world
                .write_model(
                    @Instance {
                        id: WORST, clock: 0, location: LOCATION, adventurer: 1, goblins: 8,
                        entry_draw: 0,
                    },
                );
            world.write_model(@adventurer(WORST, 1, true));
            let goblins = worst_goblins();
            for goblin in goblins.span() {
                world.write_model(goblin);
            }
            let (x, y, _) = window_origin(START_X, START_Y);
            world
                .write_model(
                    @Window {
                        instance_id: WORST, origin: origin_key(x, y), terrain: window(COMB, x, y),
                    },
                );
        }

        fn queue(ref self: ContractState) {
            let mut world = self.world(@"spk2");
            world
                .write_model(
                    @Instance {
                        id: QUEUE, clock: 0, location: LOCATION, adventurer: 1, goblins: 8,
                        entry_draw: 0,
                    },
                );
            world.write_model(@adventurer(QUEUE, 1, false));
            let goblins = queue_goblins();
            for goblin in goblins.span() {
                world.write_model(goblin);
            }
            let (x, y, _) = window_origin(START_X, START_Y);
            let mut step: u8 = 0;
            while step <= QUEUE_LENGTH {
                world
                    .write_model(
                        @Window {
                            instance_id: QUEUE,
                            origin: origin_key(x + step, y),
                            terrain: window(PILLARS, x + step, y),
                        },
                    );
                step += 1;
            }
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
                    @Grimoire { adventurer: 1, book: BOOK, known: 0, remaining: REGION_1_REMAINING },
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
                        id: 1, hub: HUB, level: 1, target: 10, experience: 500, gold: 20,
                        item: 400,
                    },
                );
            world
                .write_model(
                    @Quest {
                        id: 2, hub: HUB, level: 1, target: 10, experience: 500, gold: 20,
                        item: 400,
                    },
                );
            world.write_model(@QuestLog { adventurer: 3, quest: 2, status: 1, progress: 10 });
            world.write_model(@Location { id: LOCATION, hub: HUB, level: 1, x: START_X, y: START_Y });
            // Instances entered from the hub start after the fixtures' ids
            world.write_model(@Counter { id: 'instance', value: 100 });
        }
    }
}
