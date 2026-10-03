//! The chunk reveal as a library class (ENG-01 §1.3; ENG-05 Open question 1, decided by the
//! orchestrator on 2026-10-03): `grimworld_logic`'s `RevealTrait::reveal` declared as its own
//! class, which `Instances` calls by `library_call` with the class hash as configuration
//! (`Instances`'
//! constructor and `set_contracts`), once an invocation that reveals (`create`, `leave` to a
//! location; ENG-07's batches). It has no storage and reads nothing: the location's records as
//! `Instances` read them (`Site`), the instance's progress, the terrain of the revealed neighbours
//! and the chunks to reveal in; the progress and the chunks revealed out, each as its two words
//! packed as stored (`(chunk, terrain, features)`), which `Instances` writes as they are (its
//! typed slots: no packer of a chunk in its class, D-200).

#[starknet::contract]
pub mod RevealLibrary {
    use starknet::storage_access::StorePacking;
    use crate::interface::IRevealLibrary;
    use crate::models::chunk::{Features, FeaturesStorePacking, Terrain, TerrainStorePacking};
    use crate::types::reveal::{Progress, RevealTrait, Site};

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
        ) -> (Progress, Span<(u8, felt252, felt252)>) {
            let mut progress = progress;
            let revealed = RevealTrait::reveal(@site, ref progress, instance_id, known, chunks);
            let mut words: Array<(u8, felt252, felt252)> = array![];
            for chunk in revealed {
                words
                    .append(
                        (
                            chunk.chunk,
                            StorePacking::<Terrain, felt252>::pack(chunk.terrain),
                            StorePacking::<Features, felt252>::pack(chunk.features),
                        ),
                    );
            }
            (progress, words.span())
        }
    }
}
