//! The executor as its own library class (CBT-05a, route (c), the project manager 2026-10-02):
//! `TickLibrary` calls it once a carrier with the actors the carrier can reach, as their in-call
//! values (their hot fields and what each derived once: no load or store of their words here), and
//! the batch's content, whose sheets it builds. It runs the carrier (`types::executor`, with
//! SPK-15's L3) and returns the actors and the kills.

#[starknet::contract]
pub mod ExecutorLibrary {
    use crate::interface::IExecutorLibrary;
    use crate::models::index::{Goblin, Member};
    use crate::types::executor::{Board, Cache, Carrier, ExecutorTrait, Levered};
    use crate::types::tick::{Content, ContentTrait};
    use crate::types::world::{Actor, WorldTrait};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl ExecutorLibraryImpl of IExecutorLibrary<ContractState> {
        fn execute(
            self: @ContractState,
            members: Array<Member>,
            goblins: Array<Goblin>,
            content: Content,
            board: Board,
            cache: Cache,
            source: Actor,
            carrier: Carrier,
            address: u16,
            t: u32,
        ) -> (Array<Member>, Array<Goblin>, Array<u16>, Cache) {
            let sheets = content.sheets();
            let mut world = WorldTrait::new(t, members, goblins, array![], false);
            let mut cache = cache;
            ExecutorTrait::execute(
                @Levered {}, ref cache, ref world, @sheets, @board, source, carrier, address, t,
            );
            let (members, goblins, killed) = world.actors();
            (members, goblins, killed, cache)
        }
    }
}
