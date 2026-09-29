//! The world tick's library class (ENG-01 §1.3, CBT-02): `grimworld_logic`'s pipeline declared as
//! its own class, which `Instances` calls by `library_call` with the class hash as configuration,
//! state in and state out, once per invocation. It has no storage and reads nothing: its only
//! entrypoint is the pipeline, with the rules of the lots written so far (`tick::Idle` until
//! CBT-05 and ENG-07 give the executor and the AI).

#[starknet::contract]
pub mod TickLibrary {
    use crate::interface::ITickLibrary;
    use crate::tick::{Idle, TickTrait};
    use crate::types::tick::{Content, World};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl TickLibraryImpl of ITickLibrary<ContractState> {
        fn run(self: @ContractState, world: World, content: Content, ticks: u8) -> World {
            let mut world = world;
            let mut rules = Idle {};
            TickTrait::run(ref world, @content, ticks, ref rules);
            world
        }
    }
}
