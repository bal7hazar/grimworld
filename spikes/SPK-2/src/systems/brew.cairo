//! A brewing step in a hub (design/07 *Discovery algorithm*), with and without the rarity
//! signature of D-52: the two entrypoints differ only in `alchemy::discover`'s `signed`.

#[starknet::interface]
pub trait IBrew<T> {
    /// Brews the pair `a < b` of a book, with the rarity signature.
    fn brew(ref self: T, adventurer: u32, book: u32, a: u8, b: u8) -> u8;
    /// The same step without the rarity signature.
    fn brew_unsigned(ref self: T, adventurer: u32, book: u32, a: u8, b: u8) -> u8;
}

#[dojo::contract]
pub mod brew {
    use dojo::model::ModelStorage;
    use dojo::world::WorldStorage;
    use spk2::alchemy::discover;
    use spk2::fate::fate;
    use spk2::models::{Adventurer, Balance, Book, Discovery, Grimoire};
    use starknet::get_caller_address;
    use super::IBrew;

    /// Consume one of an item.
    fn take(ref world: WorldStorage, owner: u32, item: u32) {
        let mut balance: Balance = world.read_model((owner, item));
        assert(balance.amount != 0, 'missing ingredient');
        balance.amount -= 1;
        world.write_model(@balance);
    }

    /// Brew; returns the result as stored in `Discovery` (1 failed, 2 + r recipe r).
    fn step(
        ref world: WorldStorage, adventurer_id: u32, book_id: u32, a: u8, b: u8, signed: bool,
    ) -> u8 {
        // [Check] Owner, in a hub, a valid pair
        let adventurer: Adventurer = world.read_model(adventurer_id);
        assert(adventurer.owner == get_caller_address().into(), 'not the owner');
        assert(adventurer.instance == 0, 'not in a hub');
        let book: Book = world.read_model(book_id);
        assert(a < b && b < book.ingredients, 'invalid pair');
        // [Compute] A known pair is deterministic, an untried one is discovered
        let pair = 16 * a + b;
        let mut discovery: Discovery = world.read_model((adventurer_id, book_id, pair));
        if discovery.result == 0 {
            let mut grimoire: Grimoire = world.read_model((adventurer_id, book_id));
            let found = discover(@book, ref grimoire, a, b, fate('brew'), signed);
            discovery.result = match found {
                Option::Some(recipe) => 2 + recipe,
                Option::None => 1,
            };
            world.write_model(@grimoire);
            world.write_model(@discovery);
        }
        // [Write] Ingredients consumed, potion or failed brew granted
        take(ref world, adventurer_id, book.ingredient + a.into());
        take(ref world, adventurer_id, book.ingredient + b.into());
        let item = if discovery.result == 1 {
            book.failed
        } else {
            book.potion + (discovery.result - 2).into()
        };
        let mut balance: Balance = world.read_model((adventurer_id, item));
        balance.amount += 1;
        world.write_model(@balance);
        discovery.result
    }

    #[abi(embed_v0)]
    impl BrewImpl of IBrew<ContractState> {
        fn brew(ref self: ContractState, adventurer: u32, book: u32, a: u8, b: u8) -> u8 {
            let mut world = self.world(@"spk2");
            step(ref world, adventurer, book, a, b, true)
        }

        fn brew_unsigned(ref self: ContractState, adventurer: u32, book: u32, a: u8, b: u8) -> u8 {
            let mut world = self.world(@"spk2");
            step(ref world, adventurer, book, a, b, false)
        }
    }
}
