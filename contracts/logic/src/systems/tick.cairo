//! The world tick's library class (ENG-01 §1.3, CBT-02): `grimworld_logic`'s pipeline declared as
//! its own class, which `Instances` calls by `library_call` with the class hash as configuration,
//! once per invocation: the stored words in, the stored words out. It has no storage and reads
//! nothing: it loads the actors' hot fields once, runs the ticks with the rules of the lots written
//! so far (the executor's, `types::executor::Executor`, CBT-05a; perception and the AI are
//! ENG-07's), and stores them back. The tick's board (the window and where it lies, D-120) comes
//! with the call: ENG-07 assembles it.

#[starknet::contract]
pub mod TickLibrary {
    use crate::interface::ITickLibrary;
    use crate::types::executor::{Board, ExecutorTrait};
    use crate::types::tick::Content;
    use crate::types::world::{TickTrait, Words, WordsTrait, WorldStoreTrait};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl TickLibraryImpl of ITickLibrary<ContractState> {
        fn run(
            self: @ContractState, words: Words, content: Content, board: Board, ticks: u8,
        ) -> Words {
            let (mut world, sheets) = words.load(@content);
            let mut rules = ExecutorTrait::new(board);
            TickTrait::run(ref world, @sheets, ticks, ref rules);
            world.store()
        }
    }
}
