//! The executor as its own library class (CBT-05a, route (c), option (2): the project manager,
//! 2026-10-02; ENG-01 §1.3): `TickLibrary`'s step-1 hook (`types::executor::Delegate`) calls it
//! once a carrier, with the words of the actors the carrier can reach and the batch's content. It
//! loads them, runs the carrier (`types::executor`, with SPK-15's L3) and returns the words. One
//! entrypoint, `execute`: step 1's carrier (the hook turns the slot into a carrier and checks its
//! legality at resolution) and, with CBT-05b, the action phase's immediate carrier.

#[starknet::contract]
pub mod ExecutorLibrary {
    use crate::interface::IExecutorLibrary;
    use crate::types::executor::{Board, Cache, Carrier, Executed, ExecutorTrait, Levered};
    use crate::types::tick::Content;
    use crate::types::world::{Actor, Words, WordsTrait, WorldStoreTrait};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl ExecutorLibraryImpl of IExecutorLibrary<ContractState> {
        fn execute(
            self: @ContractState,
            words: Words,
            content: Content,
            board: Board,
            cache: Cache,
            source: Actor,
            carrier: Carrier,
            address: u16,
            t: u32,
        ) -> (Words, Cache, bool) {
            let (mut world, sheets) = words.load(@content);
            let mut cache = cache;
            let executed = ExecutorTrait::execute(
                @Levered {}, ref cache, ref world, @sheets, @board, source, carrier, address, t,
            );
            (world.store(), cache, executed == Executed::Place)
        }
    }
}
