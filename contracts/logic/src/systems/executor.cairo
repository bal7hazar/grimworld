//! The executor as its own library class (CBT-05a; ENG-01 §1.3): `TickLibrary` would call it once
//! a carrier, with the words of the actors the carrier can reach and the sheets their loads need.
//! It loads them, runs the carrier (`types::executor`, with SPK-15's L3) and returns the words.
//! Built to measure the own-class route against the single class.

#[starknet::contract]
pub mod ExecutorLibrary {
    use crate::interface::IExecutorLibrary;
    use crate::types::executor::{Board, Cache, Carrier, ExecutorTrait, Levered};
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
        ) -> (Words, Cache) {
            let (mut world, sheets) = words.load(@content);
            let mut cache = cache;
            ExecutorTrait::execute(
                @Levered {}, ref cache, ref world, @sheets, @board, source, carrier, address, t,
            );
            (world.store(), cache)
        }
    }
}
