//! A location's quota hosts as a library class (ENG-01 §1.3; ENG-05, D-208, D-210, the project
//! manager, 2026-10-04): `grimworld_logic`'s `PlacementTrait::hosts` declared as its own class,
//! which `Instances` calls by `library_call` with the class hash as configuration (`Instances`'
//! constructor and `set_contracts`), once at `create` in a zone with quotas. It has no storage and
//! reads nothing: the zone, its rectangle, the quotas' plan (`PlacementTrait::plan`: each count,
//! kind and param), the location's set pieces, the masks of the chunks to reveal and the seed
//! in; one bitmap a quota, and the masks with their chunks' hosts above the board, out. A
//! generated zone's; an authored zone's quotas are drawn among the author's candidates instead
//! (D-214, D-215 ruling 3; ENG-08's format, ENG-09: `enter` and `reveal` below). A dungeon floor's
//! call (`floor`, ENG-10b;
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
//!
//! **An authored zone** (a zone whose `LOCATION` carries the marker, `Location::authored`; D-214,
//! D-215, ENG-09) is revealed here, not by `RevealLibrary`: its site (`authored_site`) reads the
//! `ZONE_CHUNK` records of the chunks to reveal and, at `enter`, its `CANDIDATES`; its quotas'
//! hosts are drawn once at `enter` among the candidates (`AuthoredTrait::hosts`, counter 226) and
//! stored by `Instances` as a generated zone's are; each chunk is composed here from its record
//! and the hosts (`AuthoredTrait::compose`: its plane, its objects, the packs to lay), then
//! `RevealLibrary`'s second entrypoint, `authored`, lays the packs with what is drawn from the
//! chunk's own word (`AuthoredTrait::lay`; the placement code is `RevealLibrary`'s already). The
//! generated path, `RevealLibrary::reveal` and its vectors, is unchanged: the fallback of every
//! zone without the marker (D-215 ruling 7).

#[starknet::contract]
pub mod HostsLibrary {
    use starknet::{ClassHash, ContractAddress};
    use crate::content::{
        CANDIDATES, OUTLINE, PACK, QUOTAS, SET_PIECE, SPAWN_TABLE, ZONE_CHUNK, exists,
    };
    use crate::fate::EntropyTrait;
    use crate::interface::{
        IHostsLibrary, IRegistryReadDispatcher, IRegistryReadDispatcherTrait,
        IRevealLibraryDispatcherTrait, IRevealLibraryLibraryDispatcher,
    };
    use crate::models::candidates::{CandidatesRecord, CandidatesTrait};
    use crate::models::chunk::Terrain;
    use crate::models::location::{Location, LocationTrait};
    use crate::models::outline::{CHUNK_SET, OutlineRecord, OutlineTrait as RecordOutlineTrait};
    use crate::models::pack::{Pack, PackRecord};
    use crate::models::quotas::{QuotaSet, QuotaSetRecord, kind as quota_kind};
    use crate::models::set_piece::{SetPiece, SetPieceRecord};
    use crate::models::spawn_table::{SpawnTable, SpawnTableRecord};
    use crate::models::zone_chunk::{ZoneChunk, ZoneChunkRecord, ZoneChunkTrait};
    use crate::snapshot::TaskEntry;
    use crate::types::reveal::authored::AuthoredTrait;
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
            if location.target == 0 && location.authored() {
                let (site, records, candidates) = authored_site(
                    registry, destination, location, entry_chunk, chunks, true,
                );
                let progress = ProgressTrait::new(@site, entropy);
                let hosts = AuthoredTrait::hosts(
                    @site.quotas, candidates, EntropyTrait::authored_hosts(entropy, instance_id),
                )
                    .span();
                let pieces = AuthoredTrait::pieces(
                    @site, progress.left.span(), records, hosts, chunks,
                );
                let (progress, revealed) = IRevealLibraryLibraryDispatcher { class_hash: reveal }
                    .authored(site, progress, instance_id, pieces);
                return (progress, revealed, hosts, None);
            }
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
            if location.target == 0 && location.authored() {
                let (site, records, _) = authored_site(
                    registry, destination, location, entry_chunk, chunks, false,
                );
                let pieces = AuthoredTrait::pieces(
                    @site, progress.left.span(), records, hosts, chunks,
                );
                return IRevealLibraryLibraryDispatcher { class_hash: reveal }
                    .authored(site, progress, instance_id, pieces);
            }
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
        let packs = templates(registry, ids.span());
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
            packs,
            pieces: pieces.span(),
        }
    }

    /// What an authored zone's reveal reads (ENG-09), in the fewest calls: one `bundle` of its
    /// `QUOTAS`, its chunk set, at `enter` (`hosts`) its two `CANDIDATES` records, and the
    /// `ZONE_CHUNK` of each chunk of `chunks`; then one `records` of the `PACK` templates its Heart
    /// quotas and those chunks' spawn points name. No spawn table, set piece, mask nor task: an
    /// authored zone's packs are its spawn points, its border tiles are walls in its plane (R-20),
    /// and a task places nothing there (D-221). Returns the site, each chunk's record (a chunk
    /// without one is left out) and the six quotas' candidate sets (empty unless `hosts`).
    #[inline(never)]
    fn authored_site(
        registry: ContractAddress,
        destination: u16,
        location: Location,
        entry_chunk: u8,
        chunks: Span<u8>,
        hosts: bool,
    ) -> (Site, Span<(u8, ZoneChunk)>, Span<felt252>) {
        let registry = IRegistryReadDispatcher { contract_address: registry };
        let mut requests: Array<(u8, u32)> = array![
            (QUOTAS, destination.into()), (OUTLINE, RecordOutlineTrait::id(destination, CHUNK_SET)),
        ];
        if hosts {
            requests.append((CANDIDATES, CandidatesTrait::id(destination, 0)));
            requests.append((CANDIDATES, CandidatesTrait::id(destination, 1)));
        }
        for chunk in chunks {
            requests.append((ZONE_CHUNK, ZoneChunkTrait::id(destination, *chunk)));
        }
        let (_, _, parts) = registry.bundle(requests.span());
        // [Compute] The records, in the order asked
        let quotas: QuotaSet = QuotaSetRecord::unpack(parts.slice(0, 1));
        let chunk_set = bitmap(parts.slice(1, 1));
        let mut at: u32 = 2;
        let mut candidates: Array<felt252> = array![];
        if hosts {
            let [c0, c1, c2] = CandidatesRecord::unpack(parts.slice(2, 3)).sets;
            let [c3, c4, c5] = CandidatesRecord::unpack(parts.slice(5, 3)).sets;
            candidates = array![c0, c1, c2, c3, c4, c5];
            at = 8;
        }
        let mut ids: Array<u32> = array![];
        let mut records: Array<(u8, ZoneChunk)> = array![];
        for chunk in chunks {
            let record = parts.slice(at, 2);
            at += 2;
            if exists(record) {
                let value = ZoneChunkRecord::unpack(record);
                for spawn in value.spawns.span() {
                    add(ref ids, *spawn.template);
                }
                records.append((*chunk, value));
            }
        }
        // [Compute] The pack templates named
        for entry in quotas.quotas.span() {
            if *entry.kind == quota_kind::HEART {
                add(ref ids, *entry.param);
            }
        }
        let packs = templates(registry, ids.span());
        let site = Site {
            target: 0,
            biome: location.biome,
            level_min: location.level_min,
            level_max: location.level_max,
            width: location.width,
            height: location.height,
            entry_chunk,
            chunk_set,
            west: 0,
            north: 0,
            masks: array![].span(),
            anchors: array![].span(),
            quotas,
            tasks: array![].span(),
            spawn: SpawnTable { spawns: [Default::default(); 7], density: 0 },
            packs,
            pieces: array![].span(),
        };
        (site, records.span(), candidates.span())
    }

    /// The `PACK` templates `ids` that the registry holds, `(id, template)`, in one `records` call
    /// (none when `ids` is empty).
    #[inline(never)]
    fn templates(registry: IRegistryReadDispatcher, ids: Span<u32>) -> Span<(u16, Pack)> {
        let mut packs: Array<(u16, Pack)> = array![];
        if ids.len() != 0 {
            let records = registry.records(PACK, ids);
            let mut i: u32 = 0;
            for id in ids {
                let record = records.slice(i, 1);
                if exists(record) {
                    packs.append(((*id).try_into().unwrap(), PackRecord::unpack(record)));
                }
                i += 1;
            }
        }
        packs.span()
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
