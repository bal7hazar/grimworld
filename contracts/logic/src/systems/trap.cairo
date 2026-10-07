//! A trap's trigger as its own library class (design/19 §5.11, CBT-05b; D-222: the project
//! manager, 2026-10-07, at most 50 %): the in-class payload (`ExecutorTrait::trigger`, the hit and
//! the entries) measured 37,462 CASM felts in `TickLibrary`, beyond its room. The move's owner
//! (ENG-07) calls it once an actor entered a tile holding an unused trap, with the words of the
//! actors (the entrant, and a placer it carries), the batch's content, the tick's board and the
//! chunks it can touch; it loads them, runs `TrapTrait::trigger`, and returns them.

#[starknet::contract]
pub mod TrapLibrary {
    use crate::interface::ITrapLibrary;
    use crate::models::chunk::Features;
    use crate::types::executor::{Board, Cache, ExecutorTrait, Levered};
    use crate::types::tick::Content;
    use crate::types::trap::TrapTrait;
    use crate::types::world::{Words, WordsTrait, WorldStoreTrait};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl TrapLibraryImpl of ITrapLibrary<ContractState> {
        fn trigger(
            self: @ContractState,
            words: Words,
            content: Content,
            board: Board,
            ground: Array<(u8, Features)>,
            entrant: u16,
            position: u8,
            level: u8,
        ) -> (Words, Array<(u8, Features)>, bool) {
            let (mut world, sheets) = words.load(@content);
            let mut ground = ground;
            let triggered = match ExecutorTrait::actor(@world, entrant) {
                Some(actor) => {
                    let mut cache: Cache = Default::default();
                    TrapTrait::trigger(
                        @Levered {},
                        ref cache,
                        ref world,
                        @sheets,
                        ref ground,
                        @board,
                        actor,
                        position,
                        level,
                    )
                },
                None => false,
            };
            (world.store(), ground, triggered)
        }
    }
}
