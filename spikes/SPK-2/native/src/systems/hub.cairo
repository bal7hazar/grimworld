//! The persistent contract (ADR-0007): adventurers, balances, alchemy, quests, gates. The measured
//! actions are part 1's `brew` and `hub` systems; `enter` opens the instance on the ephemeral
//! contract, which sends the results back through `apply_results` on leaving.

use spk2n::models::{Adventurer, Grimoire};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IHub<T> {
    fn set_instances(ref self: T, instances: ContractAddress);
    /// Adventurers 1 (signed) and 2 (unsigned) in hub 1, the Region 1 book, ingredients.
    fn setup_alchemy(ref self: T, owner: ContractAddress);
    /// Adventurer 3 in hub 1, quests 1 (to accept) and 2 (done, to claim), location 10.
    fn setup_hub(ref self: T, owner: ContractAddress);
    fn accept_quest(ref self: T, adventurer: u32, quest: u32);
    fn claim_quest(ref self: T, adventurer: u32, quest: u32);
    fn brew(ref self: T, adventurer: u32, book: u32, a: u8, b: u8) -> u8;
    fn brew_unsigned(ref self: T, adventurer: u32, book: u32, a: u8, b: u8) -> u8;
    fn enter(ref self: T, adventurer: u32, location: u32) -> u32;
    /// The narrow interface: only the registered ephemeral contract.
    fn apply_results(ref self: T, adventurer: u32, experience: u32);
    fn adventurer(self: @T, id: u32) -> Adventurer;
    fn balance(self: @T, owner: u32, item: u32) -> u32;
    fn grimoire(self: @T, adventurer: u32, book: u32) -> Grimoire;
    fn discovery(self: @T, adventurer: u32, book: u32, pair: u8) -> u8;
    fn quest_log(self: @T, adventurer: u32, quest: u32) -> (u8, u16);
}

#[starknet::contract]
pub mod Hub {
    use spk2n::alchemy::{
        REGION_1_MASKS, REGION_1_PAIRS, REGION_1_RARITIES, REGION_1_RECIPES, REGION_1_REMAINING,
        discover,
    };
    use spk2n::fate::fate;
    use spk2n::fixtures::{START_X, START_Y};
    use spk2n::models::{
        Adventurer, Book, Grimoire, Location, Quest, pack_book_meta, pack_grimoire, pack_hero,
        pack_location, pack_quest, unpack_book, unpack_grimoire, unpack_hero, unpack_location,
        unpack_quest,
    };
    use spk2n::systems::instances::{IInstancesDispatcher, IInstancesDispatcherTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};

    pub const HUB: u32 = 1;
    pub const BOOK: u32 = 1;
    pub const INGREDIENT: u32 = 100;
    pub const POTION: u32 = 200;
    pub const FAILED: u32 = 300;
    pub const LOCATION: u32 = 10;
    /// A quest log: status (0 none, 1 accepted, 2 claimed) + 256 × progress.
    const STATUS: NonZero<u32> = 0x100;

    #[storage]
    struct Storage {
        admin: ContractAddress,
        instances: ContractAddress,
        owners: Map<u32, ContractAddress>,
        /// `pack_hero`
        heroes: Map<u32, felt252>,
        balances: Map<(u32, u32), u32>,
        book_meta: Map<u32, felt252>,
        book_masks: Map<u32, u128>,
        /// (adventurer, book) -> `pack_grimoire`
        grimoires: Map<(u32, u32), u128>,
        /// (adventurer, book, pair) -> 0 untried, 1 failed, 2 + r recipe r
        discoveries: Map<(u32, u32, u8), u8>,
        quests: Map<u32, felt252>,
        logs: Map<(u32, u32), u32>,
        locations: Map<u32, u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Acted: Acted,
    }

    /// A hub action: what it was and its result, for the indexer and the client.
    #[derive(Drop, starknet::Event)]
    pub struct Acted {
        #[key]
        pub adventurer: u32,
        pub action: felt252,
        pub value: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.admin.write(admin);
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn only_admin(self: @ContractState) {
            assert(get_caller_address() == self.admin.read(), 'not the admin');
        }

        fn owned(self: @ContractState, id: u32) -> Adventurer {
            assert(self.owners.read(id) == get_caller_address(), 'not the owner');
            unpack_hero(id, self.heroes.read(id))
        }

        fn write_hero(ref self: ContractState, id: u32, level: u8, owner: ContractAddress) {
            self.owners.write(id, owner);
            let hero = Adventurer {
                id, level, experience: 1000, gold: 50, hub: HUB, instance: 0,
            };
            self.heroes.write(id, pack_hero(@hero));
        }

        fn take(ref self: ContractState, owner: u32, item: u32) {
            let amount = self.balances.read((owner, item));
            assert(amount != 0, 'missing ingredient');
            self.balances.write((owner, item), amount - 1);
        }

        fn step(
            ref self: ContractState, adventurer_id: u32, book_id: u32, a: u8, b: u8, signed: bool,
        ) -> u8 {
            // [Check] Owner, in a hub, a valid pair
            let adventurer = self.owned(adventurer_id);
            assert(adventurer.instance == 0, 'not in a hub');
            let book = unpack_book(
                book_id, self.book_meta.read(book_id), self.book_masks.read(book_id),
            );
            assert(a < b && b < book.ingredients, 'invalid pair');
            // [Compute] A known pair is deterministic, an untried one is discovered
            let pair = 16 * a + b;
            let mut result = self.discoveries.read((adventurer_id, book_id, pair));
            if result == 0 {
                let key = (adventurer_id, book_id);
                let mut grimoire = unpack_grimoire(adventurer_id, book_id, self.grimoires.read(key));
                let found = discover(@book, ref grimoire, a, b, fate('brew'), signed);
                result = match found {
                    Option::Some(recipe) => 2 + recipe,
                    Option::None => 1,
                };
                self.grimoires.write(key, pack_grimoire(@grimoire));
                self.discoveries.write((adventurer_id, book_id, pair), result);
            }
            // [Write] Ingredients consumed, potion or failed brew granted
            self.take(adventurer_id, book.ingredient + a.into());
            self.take(adventurer_id, book.ingredient + b.into());
            let item = if result == 1 {
                book.failed
            } else {
                book.potion + (result - 2).into()
            };
            let amount = self.balances.read((adventurer_id, item));
            self.balances.write((adventurer_id, item), amount + 1);
            self.emit(Acted { adventurer: adventurer_id, action: 'brew', value: result.into() });
            result
        }
    }

    #[abi(embed_v0)]
    impl HubImpl of super::IHub<ContractState> {
        fn set_instances(ref self: ContractState, instances: ContractAddress) {
            self.only_admin();
            self.instances.write(instances);
        }

        fn setup_alchemy(ref self: ContractState, owner: ContractAddress) {
            self.only_admin();
            let book = Book {
                id: BOOK,
                ingredients: 10,
                rarities: REGION_1_RARITIES,
                masks: REGION_1_MASKS,
                recipes: REGION_1_RECIPES,
                ingredient: INGREDIENT,
                potion: POTION,
                failed: FAILED,
            };
            self.book_meta.write(BOOK, pack_book_meta(@book));
            self.book_masks.write(BOOK, REGION_1_MASKS);
            // Adventurer 1 brews with signatures, adventurer 2 without
            self.write_hero(1, 20, owner);
            self.write_hero(2, 20, owner);
            self
                .grimoires
                .write(
                    (1, BOOK),
                    pack_grimoire(
                        @Grimoire { adventurer: 1, book: BOOK, known: 0, remaining: REGION_1_REMAINING },
                    ),
                );
            self
                .grimoires
                .write(
                    (2, BOOK),
                    pack_grimoire(
                        @Grimoire { adventurer: 2, book: BOOK, known: 0, remaining: REGION_1_PAIRS },
                    ),
                );
            let mut item: u32 = 0;
            while item != 10 {
                self.balances.write((1, INGREDIENT + item), 10);
                self.balances.write((2, INGREDIENT + item), 10);
                item += 1;
            }
        }

        fn setup_hub(ref self: ContractState, owner: ContractAddress) {
            self.only_admin();
            self.write_hero(3, 20, owner);
            let quest = Quest {
                id: 1, hub: HUB, level: 1, target: 10, experience: 500, gold: 20, item: 400,
            };
            self.quests.write(1, pack_quest(@quest));
            self.quests.write(2, pack_quest(@Quest { id: 2, ..quest }));
            self.logs.write((3, 2), 1 + 256 * 10);
            self
                .locations
                .write(
                    LOCATION,
                    pack_location(@Location { id: LOCATION, hub: HUB, level: 1, x: START_X, y: START_Y }),
                );
        }

        fn accept_quest(ref self: ContractState, adventurer: u32, quest: u32) {
            let owner = self.owned(adventurer);
            assert(owner.instance == 0, 'not in a hub');
            let registry = unpack_quest(quest, self.quests.read(quest));
            assert(registry.hub == owner.hub, 'quest not here');
            assert(registry.level <= owner.level, 'level too low');
            let log = self.logs.read((adventurer, quest));
            assert(log == 0, 'already accepted');
            self.logs.write((adventurer, quest), 1);
            self.emit(Acted { adventurer, action: 'accept', value: quest });
        }

        fn claim_quest(ref self: ContractState, adventurer: u32, quest: u32) {
            let mut owner = self.owned(adventurer);
            assert(owner.instance == 0, 'not in a hub');
            let registry = unpack_quest(quest, self.quests.read(quest));
            assert(registry.hub == owner.hub, 'quest not here');
            let (progress, status) = DivRem::div_rem(self.logs.read((adventurer, quest)), STATUS);
            assert(status == 1 && progress >= registry.target.into(), 'not done');
            owner.experience += registry.experience;
            owner.gold += registry.gold;
            let amount = self.balances.read((adventurer, registry.item));
            self.logs.write((adventurer, quest), 2 + 256 * progress);
            self.heroes.write(adventurer, pack_hero(@owner));
            self.balances.write((adventurer, registry.item), amount + 1);
            self.emit(Acted { adventurer, action: 'claim', value: quest });
        }

        fn brew(ref self: ContractState, adventurer: u32, book: u32, a: u8, b: u8) -> u8 {
            self.step(adventurer, book, a, b, true)
        }

        fn brew_unsigned(ref self: ContractState, adventurer: u32, book: u32, a: u8, b: u8) -> u8 {
            self.step(adventurer, book, a, b, false)
        }

        fn enter(ref self: ContractState, adventurer: u32, location: u32) -> u32 {
            let mut owner = self.owned(adventurer);
            assert(owner.instance == 0, 'already in an instance');
            let gate = unpack_location(location, self.locations.read(location));
            assert(gate.hub == owner.hub, 'no gate here');
            assert(gate.level <= owner.level, 'level too low');
            let id = IInstancesDispatcher { contract_address: self.instances.read() }
                .open(get_caller_address(), adventurer, location, gate.x, gate.y, owner.level);
            owner.instance = id;
            self.heroes.write(adventurer, pack_hero(@owner));
            self.emit(Acted { adventurer, action: 'enter', value: id });
            id
        }

        fn apply_results(ref self: ContractState, adventurer: u32, experience: u32) {
            assert(get_caller_address() == self.instances.read(), 'not the instances');
            let mut hero = unpack_hero(adventurer, self.heroes.read(adventurer));
            hero.instance = 0;
            hero.experience += experience;
            self.heroes.write(adventurer, pack_hero(@hero));
        }

        fn adventurer(self: @ContractState, id: u32) -> Adventurer {
            unpack_hero(id, self.heroes.read(id))
        }

        fn balance(self: @ContractState, owner: u32, item: u32) -> u32 {
            self.balances.read((owner, item))
        }

        fn grimoire(self: @ContractState, adventurer: u32, book: u32) -> Grimoire {
            unpack_grimoire(adventurer, book, self.grimoires.read((adventurer, book)))
        }

        fn discovery(self: @ContractState, adventurer: u32, book: u32, pair: u8) -> u8 {
            self.discoveries.read((adventurer, book, pair))
        }

        fn quest_log(self: @ContractState, adventurer: u32, quest: u32) -> (u8, u16) {
            let (progress, status) = DivRem::div_rem(self.logs.read((adventurer, quest)), STATUS);
            (status.try_into().unwrap(), progress.try_into().unwrap())
        }
    }
}
