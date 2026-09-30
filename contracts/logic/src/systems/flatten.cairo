//! The snapshot's flattening as a library class (ENG-01 §1.3, D-168): `grimworld_logic`'s
//! `SnapshotBuildTrait::words` declared as its own class, which `Hub.set_build` calls by
//! `library_call` with the class hash as configuration (`Hub.set_contracts`), once per build. It
//! has no storage and reads nothing: the build's records as `Hub` read them in (the loadout, the
//! items worn, the `MODIFIER` records), the snapshot's three packed words out, which `Hub` stores
//! with the adventurer and `Hub.enter` copies. A refusal of the flattening (DS-2's floors, the
//! counts, an insignia's piece) reverts `set_build`.

#[starknet::contract]
pub mod FlattenLibrary {
    use crate::interface::IFlattenLibrary;
    use crate::snapshot::{Loadout, SnapshotBuildTrait, Worn};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl FlattenLibraryImpl of IFlattenLibrary<ContractState> {
        fn words(
            self: @ContractState,
            loadout: Loadout,
            worn: Span<Worn>,
            ids: Span<u16>,
            records: Span<felt252>,
        ) -> (felt252, felt252, felt252) {
            SnapshotBuildTrait::words(@loadout, worn, ids, records)
        }
    }
}
