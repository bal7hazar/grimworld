//! The snapshot's flattening as a library class (ENG-01 §1.3, D-168): `grimworld_logic`'s
//! `SnapshotBuildTrait::words` declared as its own class, which `Hub.set_build` calls by
//! `library_call` with the class hash as configuration (`Hub.set_contracts`), once per build. It
//! has no storage and reads nothing: the build and the records `Hub` read for it in (the
//! `Registry.bundle` parts of the bar's skills, the belt's items and the modifiers worn; the items
//! worn), the snapshot's three packed words out, which `Hub` stores with the adventurer and
//! `Hub.enter` copies. Since WPN-01 it also runs the checks of those parts and builds the loadout
//! (`models::sent_build::BuildTrait::words`), out of `Hub`'s class (D-310). A refusal (the bar's,
//! the belt's potions, DS-2's floors, the counts, an insignia's piece) reverts `set_build`.

#[starknet::contract]
pub mod FlattenLibrary {
    use starknet::storage_access::StorePacking;
    use crate::interface::IFlattenLibrary;
    use crate::models::sent_build::{Build, BuildTrait};
    use crate::models::worn::Worn;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl FlattenLibraryImpl of IFlattenLibrary<ContractState> {
        fn words(
            self: @ContractState,
            build: felt252,
            known: Span<bool>,
            parts: Span<felt252>,
            level: u8,
            primary: u8,
            secondary: u8,
            potions: u32,
            weapon: u128,
            requirement: u8,
            personalised: bool,
            belt: [u32; 4],
            counts: [u8; 4],
            worn: Span<Worn>,
            ids: Span<u16>,
        ) -> (felt252, felt252, felt252) {
            let build: Build = StorePacking::unpack(build);
            build
                .words(
                    known,
                    parts,
                    level,
                    primary,
                    secondary,
                    potions,
                    weapon,
                    requirement,
                    personalised,
                    belt,
                    counts,
                    worn,
                    ids,
                )
        }
    }
}
