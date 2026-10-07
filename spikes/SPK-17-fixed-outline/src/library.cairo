//! The spike's classes, measured by their CASM felts against D-200, D-209 and D-210 and called by
//! the cost tests as `Instances` calls ENG-05's: `FloorLibrary`, `HostsLibrary` as ENG-10b would
//! make it (a zone's hosts as before; a dungeon floor's outline and hosts in one call at `create`);
//! `FixedRevealLibrary`, `RevealLibrary` on the changed engine; `Slots`, the instance's new slots
//! apart.

use grimworld_logic::models::chunk::Terrain;
use grimworld_logic::models::set_piece::SetPiece;
use crate::engine::{Progress, Site};
use crate::outline::Outline;

#[starknet::interface]
pub trait IFloorLibrary<T> {
    /// A zone's hosts, as ENG-05's `HostsLibrary::hosts`.
    fn hosts(
        self: @T,
        zone: felt252,
        width: u8,
        height: u8,
        plan: (felt252, felt252),
        pieces: Span<(u16, SetPiece)>,
        masks: Span<(u8, felt252)>,
        seed: felt252,
    ) -> (Span<felt252>, Span<(u8, felt252)>);
    /// A dungeon floor at `create`: its outline (`outline_seed`), its hosts (`hosts_seed`, the exit
    /// and the Heart among its farthest chunks) and the masks of `chunks`, the chunks the entry
    /// reveals, with their hosts above the board.
    fn floor(
        self: @T,
        entry: u8,
        n: u8,
        width: u8,
        height: u8,
        plan: (felt252, felt252),
        pieces: Span<(u16, SetPiece)>,
        chunks: Span<u8>,
        outline_seed: felt252,
        hosts_seed: felt252,
    ) -> (Outline, Span<felt252>, Span<(u8, felt252)>);
}

#[starknet::contract]
pub mod FloorLibrary {
    use grimworld_logic::models::set_piece::SetPiece;
    use crate::engine::placement::PlacementTrait;
    use crate::outline::{Outline, OutlineTrait};
    use super::IFloorLibrary;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl FloorLibraryImpl of IFloorLibrary<ContractState> {
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
            let hosts = PlacementTrait::hosts(zone, width, height, plan, pieces, seed, 0).span();
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
            outline_seed: felt252,
            hosts_seed: felt252,
        ) -> (Outline, Span<felt252>, Span<(u8, felt252)>) {
            let outline = OutlineTrait::draw(entry, n, width, height, outline_seed);
            let (far, _) = outline.far(entry);
            let hosts = PlacementTrait::hosts(
                outline.chunks, width, height, plan, pieces, hosts_seed, far,
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

#[starknet::interface]
pub trait IFixedRevealLibrary<T> {
    fn reveal(
        self: @T,
        site: Site,
        progress: Progress,
        instance_id: felt252,
        known: Span<(u8, Terrain)>,
        chunks: Span<u8>,
    ) -> (Progress, Span<(u8, felt252, felt252)>);
}

/// `grimworld_logic::systems::reveal::RevealLibrary` on the changed engine, line for line.
#[starknet::contract]
pub mod FixedRevealLibrary {
    use grimworld_logic::models::chunk::{Features, FeaturesStorePacking, Terrain, TerrainStorePacking};
    use starknet::storage_access::StorePacking;
    use crate::engine::{Progress, RevealTrait, Site};
    use super::IFixedRevealLibrary;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl FixedRevealLibraryImpl of IFixedRevealLibrary<ContractState> {
        fn reveal(
            self: @ContractState,
            site: Site,
            progress: Progress,
            instance_id: felt252,
            known: Span<(u8, Terrain)>,
            chunks: Span<u8>,
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

/// The slots `create` writes for a floor, shaped as `Instances`' (`hosts` under `(slot, quota)`;
/// the outline's three felts under `(slot, 0–2)`), to measure them apart.
#[starknet::interface]
pub trait ISlots<T> {
    fn write(ref self: T, slot: u32, outline: Outline, hosts: Span<felt252>);
    fn nothing(ref self: T, slot: u32, outline: Outline, hosts: Span<felt252>);
}

#[starknet::contract]
pub mod Slots {
    use starknet::storage::{Map, StorageMapWriteAccess};
    use crate::outline::Outline;
    use super::ISlots;

    #[storage]
    struct Storage {
        outline: Map<(u32, u8), felt252>,
        hosts: Map<(u32, u8), felt252>,
    }

    #[abi(embed_v0)]
    impl SlotsImpl of ISlots<ContractState> {
        fn write(ref self: ContractState, slot: u32, outline: Outline, hosts: Span<felt252>) {
            self.outline.write((slot, 0), outline.chunks);
            self.outline.write((slot, 1), outline.west);
            self.outline.write((slot, 2), outline.north);
            let mut quota: u8 = 0;
            for mask in hosts {
                if *mask != 0 {
                    self.hosts.write((slot, quota), *mask);
                }
                quota += 1;
            }
        }

        /// The same call, writing nothing: the pair's baseline.
        fn nothing(ref self: ContractState, slot: u32, outline: Outline, hosts: Span<felt252>) {}
    }
}
