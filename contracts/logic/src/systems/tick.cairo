//! The world tick's library class (ENG-01 §1.3, CBT-02): `grimworld_logic`'s pipeline declared as
//! its own class, which `Instances` calls by `library_call` with the class hash as configuration,
//! once per invocation: the stored words in, the stored words out. It has no storage and reads
//! nothing: it loads the actors' hot fields once, runs the ticks with the rules of the lots written
//! so far (`types::world::Idle` until CBT-05 and ENG-07 give the executor and the AI), and stores
//! them back.

#[starknet::contract]
pub mod TickLibrary {
    use crate::interface::ITickLibrary;
    use crate::types::tick::Content;
    use crate::types::world::{Idle, TickTrait, Words, WordsTrait, WorldStoreTrait};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl TickLibraryImpl of ITickLibrary<ContractState> {
        fn run(self: @ContractState, words: Words, content: Content, ticks: u8) -> Words {
            let mut world = words.load(@content);
            let mut rules = Idle {};
            TickTrait::run(ref world, @content, ticks, ref rules);
            world.store()
        }
    }
}
