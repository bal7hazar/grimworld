//! The adventurer's combat action as its own library class (D-233, the project manager,
//! 2026-10-07; design/19 §5.3, CBT-05b): `TickLibrary`'s segment calls it only for an Attack, a
//! Skill or an Item, with the whole words, the batch's content, the tick's board and the chunk
//! objects; Move, Turn, Wait and the Interact refusal run in the segment. It loads them, runs the
//! action phase (`ActionTrait::act`: legality, costs, facing, a carrier through
//! `ExecutorLibrary` or an activation started, a trap placed in the ground) and returns the words,
//! the ground and the action's tick cost, or why it is illegal (then the words as they came: the
//! batch stops). The ticks are the segment's.

#[starknet::contract]
pub mod ActionLibrary {
    use core::num::traits::Zero;
    use starknet::ClassHash;
    use crate::actions::Action;
    use crate::interface::IActionLibrary;
    use crate::models::chunk::Features;
    use crate::types::action::{ActionTrait, Illegal};
    use crate::types::executor::{Board, Delegate};
    use crate::types::tick::Content;
    use crate::types::world::{Words, WordsTrait, WorldStoreTrait};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl ActionLibraryImpl of IActionLibrary<ContractState> {
        fn act(
            self: @ContractState,
            words: Words,
            content: Content,
            board: Board,
            executor: ClassHash,
            ground: Array<(u8, Features)>,
            action: Action,
        ) -> (Words, Array<(u8, Features)>, Result<u8, Illegal>) {
            let (mut world, sheets, index) = words.clone().indexed(@content);
            let mut rules = Delegate {
                board,
                cache: Default::default(),
                executor,
                content,
                index,
                placed: array![],
                ground,
                ai: Zero::zero(),
                trap: Zero::zero(),
                level: 0,
                frozen: 0,
            };
            match ActionTrait::act(ref world, @sheets, ref rules, 0, action) {
                Ok(ticks) => (world.store(), rules.ground, Ok(ticks)),
                Err(illegal) => (words, rules.ground, Err(illegal)),
            }
        }
    }
}
