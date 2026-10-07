//! A spike class holding the authored path as ENG-09 could put it in a class of its own: the
//! hosts' draw among candidates and the reveal of one authored chunk, the record decoded inside.
//! Measured by its CASM felts (ENG-08 deliverable 3, against D-200 and D-209), and called by the
//! cost tests as `Instances` calls `RevealLibrary`.

use grimworld_logic::models::quotas::QuotaSet;
use grimworld_logic::types::reveal::Site;

#[starknet::interface]
pub trait IAuthoredLibrary<T> {
    /// Each quota's hosts among its candidates: at `create`, once.
    fn hosts(self: @T, quotas: QuotaSet, candidates: Span<felt252>, seed: felt252) -> Span<felt252>;
    /// The chunk's two words from its `ZONE_CHUNK` parts: at each reveal.
    fn reveal(
        self: @T,
        site: Site,
        chunk: u8,
        parts: Span<felt252>,
        hosts: Span<felt252>,
        entropy: felt252,
        instance: felt252,
    ) -> (felt252, felt252);
}

#[starknet::contract]
pub mod AuthoredLibrary {
    use grimworld_logic::models::chunk::{FeaturesStorePacking, TerrainStorePacking};
    use grimworld_logic::models::quotas::QuotaSet;
    use grimworld_logic::types::reveal::Site;
    use crate::authored::AuthoredTrait;
    use crate::zone_chunk::ZoneChunkRecord;
    use super::IAuthoredLibrary;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl AuthoredLibraryImpl of IAuthoredLibrary<ContractState> {
        fn hosts(
            self: @ContractState, quotas: QuotaSet, candidates: Span<felt252>, seed: felt252,
        ) -> Span<felt252> {
            AuthoredTrait::hosts(@quotas, candidates, seed).span()
        }

        fn reveal(
            self: @ContractState,
            site: Site,
            chunk: u8,
            parts: Span<felt252>,
            hosts: Span<felt252>,
            entropy: felt252,
            instance: felt252,
        ) -> (felt252, felt252) {
            let record = ZoneChunkRecord::unpack(parts);
            let (terrain, features) = AuthoredTrait::reveal(
                @site, chunk, @record, hosts, entropy, instance,
            );
            (TerrainStorePacking::pack(terrain), FeaturesStorePacking::pack(features))
        }
    }
}

/// A slot store shaped as `Instances`' chunks (two consecutive felts under `(slot, chunk)`), to
/// measure the copy of an authored chunk's two words into an instance (ruling 2) apart.
#[starknet::interface]
pub trait IChunkSlots<T> {
    fn write(ref self: T, slot: u32, chunk: u8, terrain: felt252, features: felt252);
    fn nothing(ref self: T, slot: u32, chunk: u8, terrain: felt252, features: felt252);
}

#[starknet::contract]
pub mod ChunkSlots {
    use starknet::storage::{Map, StorageMapWriteAccess};
    use super::IChunkSlots;

    #[storage]
    struct Storage {
        terrain: Map<(u32, u8), felt252>,
        features: Map<(u32, u8), felt252>,
    }

    #[abi(embed_v0)]
    impl ChunkSlotsImpl of IChunkSlots<ContractState> {
        fn write(
            ref self: ContractState, slot: u32, chunk: u8, terrain: felt252, features: felt252,
        ) {
            self.terrain.write((slot, chunk), terrain);
            self.features.write((slot, chunk), features);
        }

        /// The same call, writing nothing: the pair's baseline.
        fn nothing(
            ref self: ContractState, slot: u32, chunk: u8, terrain: felt252, features: felt252,
        ) {}
    }
}
