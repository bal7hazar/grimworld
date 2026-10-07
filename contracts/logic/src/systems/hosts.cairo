//! A location's quota hosts as a library class (ENG-01 §1.3; ENG-05, D-208, D-210, the project
//! manager, 2026-10-04): `grimworld_logic`'s `PlacementTrait::hosts` declared as its own class,
//! which `Instances` calls by `library_call` with the class hash as configuration (`Instances`'
//! constructor and `set_contracts`), once at `create` in a zone with quotas. It has no storage and
//! reads nothing: the zone, its rectangle, the quotas' plan (`PlacementTrait::plan`: each count,
//! kind and param), the location's set pieces, the masks of the chunks to reveal and the seed
//! in; one bitmap a quota, and the masks with their chunks' hosts above the board, out. A
//! generated zone's; an authored zone's quotas are drawn among the author's candidates instead
//! (D-214, D-215 ruling 3; ENG-08's format, ENG-09). A dungeon floor's call (`floor`, ENG-10b;
//! ENG-10a, D-223): once at `create`, its outline (`OutlineTrait::draw`), its layers by distance
//! from the entry, its quotas' hosts over the outline (the exit and the Heart first, among the
//! farthest chunks) and the masks of the chunks the entry reveals, with their hosts.

#[starknet::contract]
pub mod HostsLibrary {
    use crate::fate::EntropyTrait;
    use crate::interface::IHostsLibrary;
    use crate::models::set_piece::SetPiece;
    use crate::types::reveal::outline::{Outline, OutlineTrait};
    use crate::types::reveal::placement::PlacementTrait;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl HostsLibraryImpl of IHostsLibrary<ContractState> {
        fn hosts(
            self: @ContractState,
            zone: felt252,
            width: u8,
            height: u8,
            plan: (felt252, felt252),
            pieces: Span<(u16, SetPiece)>,
            masks: Span<(u8, felt252)>,
            seed: felt252,
        ) -> (Span<felt252>, Span<(u8, felt252)>) {
            let hosts = PlacementTrait::hosts(
                zone, width, height, plan, pieces, seed, array![].span(),
            )
                .span();
            let mut hosted: Array<(u8, felt252)> = array![];
            for entry in masks {
                let (chunk, mask) = *entry;
                hosted.append((chunk, PlacementTrait::with_hosts(mask, hosts, chunk)));
            }
            (hosts, hosted.span())
        }

        fn floor(
            self: @ContractState,
            entry: u8,
            n: u8,
            width: u8,
            height: u8,
            plan: (felt252, felt252),
            pieces: Span<(u16, SetPiece)>,
            chunks: Span<u8>,
            entropy: felt252,
            instance_id: felt252,
        ) -> (Outline, Span<felt252>, Span<(u8, felt252)>) {
            let outline = OutlineTrait::draw(
                entry, n, width, height, EntropyTrait::outline(entropy, instance_id),
            );
            let layers = outline.layers(entry);
            let hosts = PlacementTrait::hosts(
                outline.chunks,
                width,
                height,
                plan,
                pieces,
                EntropyTrait::hosts(entropy, instance_id),
                layers.span(),
            )
                .span();
            let mut hosted: Array<(u8, felt252)> = array![];
            for chunk in chunks {
                hosted.append((*chunk, PlacementTrait::with_hosts(0, hosts, *chunk)));
            }
            (outline, hosts, hosted.span())
        }
    }
}
