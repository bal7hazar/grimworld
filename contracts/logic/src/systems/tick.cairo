//! The world tick's library class (ENG-01 §1.3, CBT-02): `grimworld_logic`'s pipeline declared as
//! its own class, which `Instances` calls by `library_call` with the class hash as configuration,
//! once per invocation: the stored words in, the stored words out. It has no storage and reads
//! nothing: it loads the actors' hot fields once, runs the ticks with the rules of the lots written
//! so far: route (c) (CBT-05a; the project manager, 2026-10-02), the executor behind its own class
//! (`ExecutorLibrary`, `executor`), called once a carrier by step 1's hook
//! (`types::executor::Delegate`); perception and the AI are ENG-07's. It stores them back. The
//! tick's board (the window and where it lies, D-120) comes with the call: ENG-07 assembles it.
//! Since ENG-07 (D-233 to D-235) its one entrypoint, `ticks`, runs the ticks with a fight that
//! `PlayLibrary`'s segment hands it (the action phase is `ActionLibrary`'s; a tick without a goblin
//! in the window runs in `PlayLibrary`), with the chunk objects carried across them (Open question
//! 3): perception and the awake set in process, the goblins' acts through `AiLibrary`.

#[starknet::contract]
pub mod TickLibrary {
    use crate::interface::ITickLibrary;
    use crate::models::chunk::Features;
    use crate::types::executor::{Board, Delegate};
    use crate::types::play::Classes;
    use crate::types::tick::Content;
    use crate::types::world::{TickTrait, Words, WordsTrait, WorldStoreTrait};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl TickLibraryImpl of ITickLibrary<ContractState> {
        fn ticks(
            self: @ContractState,
            words: Words,
            content: Content,
            board: Board,
            classes: Classes,
            level: u8,
            ground: Array<(u8, Features)>,
            ticks: u8,
        ) -> (Words, Array<(u8, Features)>) {
            let (mut world, sheets, index) = words.indexed(@content);
            let mut rules = Delegate {
                board,
                cache: Default::default(),
                executor: classes.executor,
                content,
                index,
                placed: array![],
                ground,
                ai: classes.ai,
                trap: classes.trap,
                level,
                frozen: 0,
                listed: 0,
            };
            TickTrait::run(ref world, @sheets, ticks, ref rules);
            (world.store(), rules.ground)
        }
    }
}
