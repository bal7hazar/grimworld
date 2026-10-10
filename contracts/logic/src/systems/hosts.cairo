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
//!
//! **The reveals' site** (CBT-05g, D-240): what a reveal reads of a location (`site`: the
//! registry's records, read once an invocation) is built here and never crosses back, so that
//! neither `Instances` nor `PlayLibrary` decodes or carries it. `enter` is `create`'s entry reveal
//! (the site, then a zone's quota hosts or a dungeon floor's outline and hosts, drawn once, then
//! `RevealLibrary`'s call), `reveal` a reveal in play (the site, the stored hosts and outline, then
//! `RevealLibrary`'s call); `hosts` and `floor` stay its entrypoints, which `enter` runs in
//! process.

#[starknet::contract]
pub mod HostsLibrary {
    use starknet::{ClassHash, ContractAddress};
    use crate::content::{OUTLINE, PACK, QUOTAS, SET_PIECE, SPAWN_TABLE, exists};
    use crate::fate::EntropyTrait;
    use crate::interface::{
        IHostsLibrary, IRegistryReadDispatcher, IRegistryReadDispatcherTrait,
        IRevealLibraryDispatcherTrait, IRevealLibraryLibraryDispatcher,
    };
    use crate::models::chunk::Terrain;
    use crate::models::location::Location;
    use crate::models::outline::{CHUNK_SET, OutlineRecord, OutlineTrait as RecordOutlineTrait};
    use crate::models::pack::{Pack, PackRecord};
    use crate::models::quotas::{QuotaSet, QuotaSetRecord, kind as quota_kind};
    use crate::models::set_piece::{SetPiece, SetPieceRecord};
    use crate::models::spawn_table::{SpawnTable, SpawnTableRecord};
    use crate::snapshot::TaskEntry;
    use crate::types::reveal::outline::{Outline, OutlineTrait};
    use crate::types::reveal::placement::PlacementTrait;
    use crate::types::reveal::{Progress, ProgressTrait, Site};
    /// Tasks whose quotas a reveal places (ENG-01 §3.2: the location's 6, then 8).
    const TASK_QUOTAS: u32 = 8;

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
            let hosts = PlacementTrait::hosts(zone, width, height, plan, pieces, seed).span();
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
            let hosts = PlacementTrait::floor_hosts(
                outline.chunks,
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

        fn enter(
            self: @ContractState,
            registry: ContractAddress,
            reveal: ClassHash,
            destination: u16,
            location: Location,
            entry_chunk: u8,
            entry_tile: u8,
            tasks: Span<TaskEntry>,
            chunks: Span<u8>,
            entropy: felt252,
            instance_id: felt252,
        ) -> (Progress, Span<(u8, felt252, felt252)>, Span<felt252>, Option<Outline>) {
            let mut site = site(
                registry, destination, location, entry_chunk, entry_tile, tasks, chunks,
            );
            let progress = ProgressTrait::new(@site, entropy);
            let mut hosts: Span<felt252> = array![].span();
            let mut outline: Option<Outline> = None;
            let plan = PlacementTrait::plan(@site, progress.left.span());
            if location.target != 0 {
                let (drawn, floor, masks) = self
                    .floor(
                        site.entry_chunk,
                        site.target,
                        site.width,
                        site.height,
                        plan,
                        site.pieces,
                        chunks,
                        entropy,
                        instance_id,
                    );
                hosts = floor;
                site.chunk_set = drawn.chunks;
                site.west = drawn.west;
                site.north = drawn.north;
                site.masks = masks;
                outline = Some(drawn);
            } else if plan != (0, 0) {
                let seed = EntropyTrait::hosts(entropy, instance_id);
                let (drawn, masks) = self
                    .hosts(
                        site.chunk_set,
                        site.width,
                        site.height,
                        plan,
                        site.pieces,
                        site.masks,
                        seed,
                    );
                hosts = drawn;
                site.masks = masks;
            }
            let (progress, revealed) = IRevealLibraryLibraryDispatcher { class_hash: reveal }
                .reveal(site, progress, instance_id, array![].span(), chunks);
            (progress, revealed, hosts, outline)
        }

        fn reveal(
            self: @ContractState,
            registry: ContractAddress,
            reveal: ClassHash,
            destination: u16,
            location: Location,
            entry_chunk: u8,
            entry_tile: u8,
            tasks: Span<TaskEntry>,
            hosts: Span<felt252>,
            outline: Option<(felt252, felt252, felt252)>,
            progress: Progress,
            instance_id: felt252,
            known: Span<(u8, Terrain)>,
            chunks: Span<u8>,
        ) -> (Progress, Span<(u8, felt252, felt252)>) {
            let mut site = site(
                registry, destination, location, entry_chunk, entry_tile, tasks, chunks,
            );
            let mut masks: Array<(u8, felt252)> = array![];
            if let Some((set, west, north)) = outline {
                site.chunk_set = set;
                site.west = west;
                site.north = north;
                for chunk in chunks {
                    masks.append((*chunk, PlacementTrait::with_hosts(0, hosts, *chunk)));
                }
            } else {
                for (chunk, mask) in site.masks {
                    masks.append((*chunk, PlacementTrait::with_hosts(*mask, hosts, *chunk)));
                }
            }
            site.masks = masks.span();
            IRevealLibraryLibraryDispatcher { class_hash: reveal }
                .reveal(site, progress, instance_id, known, chunks)
        }
    }

    /// What a reveal reads of `location` (`destination`'s record, read by the caller), in the
    /// fewest calls (ENG-05): one `bundle` of its `QUOTAS`, its `SPAWN_TABLE`, a zone's chunk set
    /// and the tile masks of `chunks`, and its set pieces; then one `records` of the `PACK`
    /// templates the spawn table, the Heart quotas and the set pieces name. The anchors are the
    /// entry tile (a gate anchored in the location is found by no index of the registry yet). The
    /// first 8 `tasks` give the tasks' quotas. Moved from `Instances` (CBT-05g).
    fn site(
        registry: ContractAddress,
        destination: u16,
        location: Location,
        entry_chunk: u8,
        entry_tile: u8,
        tasks: Span<TaskEntry>,
        chunks: Span<u8>,
    ) -> Site {
        let registry = IRegistryReadDispatcher { contract_address: registry };
        let zone = location.target == 0;
        let table = location.spawn_table;
        let mut requests: Array<(u8, u32)> = array![(QUOTAS, destination.into())];
        if table != 0 {
            requests.append((SPAWN_TABLE, table.into()));
        }
        if zone {
            requests.append((OUTLINE, RecordOutlineTrait::id(destination, CHUNK_SET)));
            for chunk in chunks {
                requests.append((OUTLINE, RecordOutlineTrait::id(destination, *chunk)));
            }
        }
        for piece in location.set_pieces.lanes.span() {
            if *piece != 0 {
                requests.append((SET_PIECE, (*piece).into()));
            }
        }
        let (_, _, parts) = registry.bundle(requests.span());
        // [Compute] The records, in the order asked
        let quotas: QuotaSet = QuotaSetRecord::unpack(parts.slice(0, 1));
        let mut at: u32 = 1;
        let spawn: SpawnTable = if table != 0 {
            at += 1;
            SpawnTableRecord::unpack(parts.slice(1, 1))
        } else {
            SpawnTable { spawns: [Default::default(); 7], density: 0 }
        };
        let mut chunk_set: felt252 = 0;
        let mut masks: Array<(u8, felt252)> = array![];
        if zone {
            chunk_set = bitmap(parts.slice(at, 1));
            at += 1;
            for chunk in chunks {
                masks.append((*chunk, bitmap(parts.slice(at, 1))));
                at += 1;
            }
        }
        let mut pieces: Array<(u16, SetPiece)> = array![];
        let mut ids: Array<u32> = array![];
        for piece in location.set_pieces.lanes.span() {
            if *piece != 0 {
                let record = parts.slice(at, 2);
                at += 2;
                if exists(record) {
                    let set: SetPiece = SetPieceRecord::unpack(record);
                    for entry in set.packs.span() {
                        add(ref ids, *entry.template);
                    }
                    pieces.append((*piece, set));
                }
            }
        }
        // [Compute] The pack templates named
        for entry in spawn.spawns.span() {
            add(ref ids, *entry.template);
        }
        for entry in quotas.quotas.span() {
            if *entry.kind == quota_kind::HEART {
                add(ref ids, *entry.param);
            }
        }
        let mut packs: Array<(u16, Pack)> = array![];
        if ids.len() != 0 {
            let records = registry.records(PACK, ids.span());
            let mut i: u32 = 0;
            for id in ids.span() {
                let record = records.slice(i, 1);
                if exists(record) {
                    packs.append(((*id).try_into().unwrap(), PackRecord::unpack(record)));
                }
                i += 1;
            }
        }
        let count = if tasks.len() < TASK_QUOTAS {
            tasks.len()
        } else {
            TASK_QUOTAS
        };
        Site {
            target: location.target,
            biome: location.biome,
            level_min: location.level_min,
            level_max: location.level_max,
            width: location.width,
            height: location.height,
            entry_chunk,
            chunk_set,
            west: 0,
            north: 0,
            masks: masks.span(),
            anchors: array![(entry_chunk, entry_tile)].span(),
            quotas,
            tasks: tasks.slice(0, count),
            spawn,
            packs: packs.span(),
            pieces: pieces.span(),
        }
    }

    /// An `OUTLINE` record's bitmap (0 for none).
    fn bitmap(parts: Span<felt252>) -> felt252 {
        let outline = OutlineRecord::unpack(parts);
        outline.low.into() + outline.high.into() * 0x100000000000000000000000000000000
    }

    /// `id` added to `ids` unless it is 0 or already there.
    fn add(ref ids: Array<u32>, id: u16) {
        if id == 0 {
            return;
        }
        let id: u32 = id.into();
        let mut found = false;
        for seen in ids.span() {
            if *seen == id {
                found = true;
            }
        }
        if !found {
            ids.append(id);
        }
    }
}
