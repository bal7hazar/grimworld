//! The world tick's library class (ENG-01 §1.3, CBT-02): `grimworld_logic`'s pipeline declared as
//! its own class, which `Instances` calls by `library_call` with the class hash as configuration,
//! once per invocation: the stored words in, the stored words out. It has no storage and reads
//! nothing: it loads the actors' hot fields once, runs the ticks with the rules of the lots written
//! so far: route (c) (CBT-05a; the project manager, 2026-10-02), the executor behind its own class
//! (`ExecutorLibrary`, `executor`), called once a carrier by step 1's hook
//! (`types::executor::Delegate`); perception and the AI are ENG-07's. It stores them back. The
//! tick's board (the window and where it lies, D-120) comes with the call: ENG-07 assembles it.
//! Its second entrypoint, `act`, runs one action of the batch before its ticks (design/19 §5.3,
//! CBT-05b; D-222: the class at most 88 %).

#[starknet::contract]
pub mod TickLibrary {
    use starknet::ClassHash;
    use crate::interface::ITickLibrary;
    use crate::types::executor::{Board, Delegate};
    use crate::types::tick::Content;
    use crate::types::world::{TickTrait, Words, WordsTrait, WorldStoreTrait};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl TickLibraryImpl of ITickLibrary<ContractState> {
        fn run(
            self: @ContractState,
            words: Words,
            content: Content,
            board: Board,
            executor: ClassHash,
            ai: ClassHash,
            trap: ClassHash,
            level: u8,
            ticks: u8,
        ) -> Words {
            let (mut world, sheets, index) = words.indexed(@content);
            let mut rules = Delegate {
                board,
                cache: Default::default(),
                executor,
                content,
                index,
                placed: array![],
                ground: array![],
                ai,
                trap,
                level,
                frozen: 0,
            };
            TickTrait::run(ref world, @sheets, ticks, ref rules);
            world.store()
        }
    }
}
