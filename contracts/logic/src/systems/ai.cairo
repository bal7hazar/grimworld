//! The goblins' acts as their own library class (ENG-07 Open question 1, candidate C: the
//! orchestrator, 2026-10-07; D-225): `TickLibrary`'s step-2 hook (`types::executor::Delegate`)
//! calls it once a tick, only when a goblin of the window is free to act, with the words of every
//! member and of the awake set, the batch's content, the tick's board and the chunk objects. It
//! loads them, runs step 2 (`types::ai`): each carrier through `ExecutorLibrary` and each trap a
//! goblin enters through `TrapLibrary`, as `TickLibrary` does; and returns them. Step 2's writes
//! stay in the call's world and go back once (scope 10's pending writes).

#[starknet::contract]
pub mod AiLibrary {
    use core::num::traits::Zero;
    use starknet::ClassHash;
    use crate::interface::IAiLibrary;
    use crate::models::chunk::Features;
    use crate::types::ai::AiTrait;
    use crate::types::executor::{Board, Delegate};
    use crate::types::tick::Content;
    use crate::types::world::{Words, WordsTrait, WorldStoreTrait};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl AiLibraryImpl of IAiLibrary<ContractState> {
        fn act(
            self: @ContractState,
            words: Words,
            content: Content,
            board: Board,
            executor: ClassHash,
            trap: ClassHash,
            ground: Array<(u8, Features)>,
            level: u8,
            frozen: felt252,
            listed: u8,
            resolved: u128,
        ) -> (Words, Array<(u8, Features)>) {
            let (mut world, sheets, index) = words.indexed(@content);
            let mut rules = Delegate {
                board,
                cache: Default::default(),
                executor,
                content,
                index,
                placed: array![],
                ground,
                ai: Zero::zero(),
                trap,
                level,
                frozen,
                listed,
            };
            AiTrait::step(ref world, @sheets, ref rules, resolved);
            (world.store(), rules.ground)
        }
    }
}
