//! The chunk reveal as a library class (ENG-01 §1.3; ENG-05 Open question 1, decided by the
//! orchestrator on 2026-10-03): `grimworld_logic`'s `RevealTrait::reveal` declared as its own class,
//! which `Instances` calls by `library_call` with the class hash as configuration (`Instances`'
//! constructor and `set_contracts`), once an invocation that reveals (`create`, `leave` to a
//! location; ENG-07's batches). It has no storage and reads nothing: the location's records as
//! `Instances` read them (`Site`), the instance's progress, the terrain of the revealed neighbours
//! and the chunks to reveal in; the progress and the chunks revealed out, which `Instances` writes.

#[starknet::contract]
pub mod RevealLibrary {
    use crate::interface::IRevealLibrary;
    use crate::models::chunk::Terrain;
    use crate::types::reveal::{Progress, RevealTrait, Revealed, Site};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl RevealLibraryImpl of IRevealLibrary<ContractState> {
        fn reveal(
            self: @ContractState,
            site: Site,
            progress: Progress,
            instance_id: felt252,
            known: Span<(u8, Terrain)>,
            chunks: Span<(u8, u8)>,
        ) -> (Progress, Span<Revealed>) {
            let mut progress = progress;
            let revealed = RevealTrait::reveal(@site, ref progress, instance_id, known, chunks);
            (progress, revealed.span())
        }
    }
}
