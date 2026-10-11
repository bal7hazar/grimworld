//! `ZoneChecks`: the content checks of an authored zone's records (ENG-01 §3.5's R-table; ENG-08's
//! format, built by ENG-09), and the content bounds they share with generated zones, dungeon floors
//! and gates (ENG-R1c-1), as a library class of `Registry` (the 50 % rule of ENG-01 §1.3: the
//! checks would have taken `Registry` to 63 % of the CASM limit). `Registry.set_record` calls it by
//! `library_call`, its class hash the administrator's configuration (`set_zone_checks`), so it runs
//! in `Registry`'s context: it reads `Registry`'s `records` and writes its `heart_packs`,
//! `gate_entries` and `gate_entry_counts`, declared here under the same names, hence at the same
//! addresses. It has no entrypoint of its own that a deployed contract would serve: it is never
//! deployed, only declared.

#[starknet::interface]
pub trait IZoneChecks<T> {
    /// The checks of one record about to be written (`Registry.set_record`, after the part count,
    /// the id and `LIVE`): every rule of an authored zone it takes part in, against the records it
    /// is checked with when they exist. Panics with the rule's code.
    fn check(self: @T, kind: u8, id: u32, record: Span<felt252>);
    /// A `QUOTAS` or a `GATE` written (after every check, before the write): `heart_packs` follows
    /// every location's Heart quotas (R-27's reverse check), `gate_entries` and
    /// `gate_entry_counts` the gates' entries (R-41's).
    fn index(ref self: T, kind: u8, id: u32, record: Span<felt252>);
}

#[starknet::contract]
pub mod ZoneChecks {
    use grimworld_logic::content::{
        BRIDGE, CANDIDATES, GATE, LOCATION, OUTLINE, PACK, QUOTAS, ZONE_CHUNK, parts,
    };
    use grimworld_logic::models::bridge::{
        Bridge, BridgeAssert, BridgeRecord, errors as bridge_errors,
    };
    use grimworld_logic::models::candidates::{CandidatesAssert, CandidatesRecord};
    use grimworld_logic::models::gate::{GateAssert, GateRecord};
    use grimworld_logic::models::location::{
        INDEX_BOUND, Location, LocationAssert, LocationRecord, LocationTrait, kind as location_kind,
        map,
    };
    use grimworld_logic::models::outline::{CHUNK_SET, OutlineAssert, OutlineRecord, OutlineTrait};
    use grimworld_logic::models::pack::{Pack, PackRecord};
    use grimworld_logic::models::quotas::{
        QuotaBoundsAssert, QuotaSet, QuotaSetRecord, kind as quota_kind,
    };
    use grimworld_logic::models::zone_chunk::{
        ZoneChunk, ZoneChunkAssert, ZoneChunkRecord, ZoneChunkTrait, errors as chunk_errors,
    };
    use grimworld_logic::packing::{LIVE, split};
    use grimworld_logic::types::reveal::board::BoardTrait;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};

    /// `Registry`'s variables this class reads and writes, in `Registry`'s context: the same names,
    /// the same addresses (`Registry`'s storage layout, ENG-01 §3.5).
    #[storage]
    pub struct Storage {
        pub records: Map<(u8, u32, u8), felt252>,
        pub heart_packs: Map<u32, u32>,
        pub gate_entries: Map<u32, felt252>,
        pub gate_entry_counts: Map<(u32, u8), u32>,
    }

    #[abi(embed_v0)]
    impl ZoneChecksImpl of super::IZoneChecks<ContractState> {
        fn check(self: @ContractState, kind: u8, id: u32, record: Span<felt252>) {
            if kind == LOCATION {
                self.assert_location(id, @LocationRecord::unpack(record));
            } else if kind == OUTLINE {
                self.assert_outline(id, OutlineRecord::unpack(record).bits());
            } else if kind == ZONE_CHUNK {
                self.assert_zone_chunk(id, @ZoneChunkRecord::unpack(record));
            } else if kind == CANDIDATES {
                self.assert_candidates(id, CandidatesRecord::unpack(record).sets);
            } else if kind == BRIDGE {
                self.assert_bridge(id, @BridgeRecord::unpack(record));
            } else if kind == GATE {
                self.assert_gate(id, record);
            } else if kind == QUOTAS {
                self.assert_quotas(id, @QuotaSetRecord::unpack(record));
            }
        }

        fn index(ref self: ContractState, kind: u8, id: u32, record: Span<felt252>) {
            if kind == QUOTAS {
                self.move_hearts(id, record);
            } else if kind == GATE {
                self.move_entry(id, record);
            }
        }
    }

    /// The indexes the reverse checks read (`IZoneChecks::index`). A count is lowered only while it
    /// is above 0. Since BND-01 `Registry` refuses a `GATE` and a `QUOTAS` until `set_zone_checks`,
    /// so no such record is written uncounted and a count cannot miss one: the guard stays
    /// defensive.
    #[generate_trait]
    impl IndexImpl of IndexTrait {
        /// A `QUOTAS` written: the counts of `heart_packs` move from the Heart templates the stored
        /// quotas named to those the new ones name, whatever the location (R-27 binds generated
        /// zones and dungeon floors too, ENG-R1c-1), as `name_skills` does for DS-18.
        fn move_hearts(ref self: ContractState, id: u32, record: Span<felt252>) {
            if let Some(quotas) = self.quotas(id) {
                for entry in quotas.quotas.span() {
                    if *entry.kind == quota_kind::HEART {
                        let count = self.heart_packs.read((*entry.param).into());
                        if count != 0 {
                            self.heart_packs.write((*entry.param).into(), count - 1);
                        }
                    }
                }
            }
            for entry in QuotaSetRecord::unpack(record).quotas.span() {
                if *entry.kind == quota_kind::HEART {
                    let count = self.heart_packs.read((*entry.param).into());
                    self.heart_packs.write((*entry.param).into(), count + 1);
                }
            }
        }

        /// A `GATE` written: its entry leaves the stored gate's destination and joins the new
        /// one's. `gate_entry_counts[(location, chunk)]` counts the gates entering `location` at
        /// `chunk`; `gate_entries[location]` holds those chunks, one bit each (R-41's reverse
        /// check, one read at a `LOCATION` write).
        fn move_entry(ref self: ContractState, id: u32, record: Span<felt252>) {
            let new = GateRecord::unpack(record);
            let old = self.part0(GATE, id);
            if old != 0 {
                let old = GateRecord::unpack(array![old].span());
                if old.destination == new.destination && old.entry_chunk == new.entry_chunk {
                    return;
                }
                let key = (old.destination.into(), old.entry_chunk);
                let count = self.gate_entry_counts.read(key);
                if count != 0 {
                    self.gate_entry_counts.write(key, count - 1);
                    if count == 1 {
                        let entries = self.gate_entries.read(old.destination.into());
                        self
                            .gate_entries
                            .write(
                                old.destination.into(),
                                BoardTrait::minus(entries, BoardTrait::pow(old.entry_chunk)),
                            );
                    }
                }
            }
            let key = (new.destination.into(), new.entry_chunk);
            let count = self.gate_entry_counts.read(key);
            self.gate_entry_counts.write(key, count + 1);
            if count == 0 {
                let entries = self.gate_entries.read(new.destination.into());
                self
                    .gate_entries
                    .write(
                        new.destination.into(),
                        BoardTrait::or(entries, BoardTrait::pow(new.entry_chunk)),
                    );
            }
        }
    }

    /// What a zone's checks read of a `LOCATION`, from its part 0 alone (ENG-01 §3.5's bits):
    /// whether it exists, whether it has a map (not a town nor an outpost), whether it is an
    /// authored zone (no `N`, the marker set), its rectangle, its `N` and its entry.
    #[derive(Copy, Drop)]
    pub struct Frame {
        pub exists: bool,
        pub map: bool,
        pub authored: bool,
        pub width: u8,
        pub height: u8,
        pub target: u8,
        pub entry_chunk: u8,
        pub entry_tile: u8,
    }

    /// What a zone's checks read of a `ZONE_CHUNK` but its placements: its plane, its bridges'
    /// count and the gates it names.
    #[derive(Copy, Drop)]
    pub struct Brief {
        pub walls: felt252,
        pub bridges: u8,
        pub gates: (u16, u16),
    }

    /// The content's checks of an authored zone's records (ENG-01 §3.5's R-table; ENG-08's
    /// format, built by ENG-09; the same cases as `tools/map-format/checks.json`, which the
    /// converter and the editor refuse with the same codes). **Every rule between two records is
    /// checked at the write of either, against the other when it exists** (CBT-02c's precedent,
    /// DS-18), so that no order of writes and no rewrite lets a breach through; the converter's
    /// order (`LOCATION` with the marker, the chunk set, `CANDIDATES`, `QUOTAS`, the masks, each
    /// `ZONE_CHUNK` and its `BRIDGE`s, the `GATE`s) only makes each write find what it checks
    /// against. The records of an authored zone's own kinds (`ZONE_CHUNK`, `CANDIDATES`, `BRIDGE`)
    /// are checked whatever the marker; the rules on kinds every location has (`QUOTAS`' bounds,
    /// the chunk set's R-11 and R-12, the entry's R-26) bind a zone with the marker, and the
    /// `LOCATION` write that sets it re-runs them (ENG-R1c applies the shared bounds to generated
    /// zones). The administrator pays them once; no player's call makes them again. Each read goes
    /// through the store, only the parts a rule needs, decoded only as far as it needs (the class's
    /// size, D-200); nothing is written.
    #[generate_trait]
    pub impl ZoneAssert of ZoneAssertTrait {
        /// A record's parts as stored (zeros for none).
        fn parts_of(self: @ContractState, kind: u8, id: u32) -> Span<felt252> {
            let mut out = array![];
            self.read_into(kind, id, parts(kind), ref out);
            out.span()
        }

        /// A record's part 0 (0 for none).
        fn part0(self: @ContractState, kind: u8, id: u32) -> felt252 {
            let mut out = array![];
            self.read_into(kind, id, 1, ref out);
            *out[0]
        }

        /// The frame of location `id` (`Frame`).
        fn frame(self: @ContractState, id: u32) -> Frame {
            let part = self.part0(LOCATION, id);
            let (low, high) = split(part);
            let s8: NonZero<u128> = 0x100;
            // kind 0–7, width 56–63, height 64–71, `N` 72–79
            let (_, kind) = DivRem::div_rem(low, s8);
            let (rest, width) = DivRem::div_rem(low / 0x100000000000000, s8);
            let (rest, height) = DivRem::div_rem(rest, s8);
            let (_, target) = DivRem::div_rem(rest, s8);
            let (rest, entry_chunk) = DivRem::div_rem(high, s8);
            let (rest, entry_tile) = DivRem::div_rem(rest, s8);
            let (_, marker) = DivRem::div_rem(rest, s8);
            Frame {
                exists: part != 0,
                map: part != 0
                    && kind != location_kind::TOWN.into()
                    && kind != location_kind::OUTPOST.into(),
                authored: part != 0 && target == 0 && marker == map::AUTHORED.into(),
                width: width.try_into().unwrap(),
                height: height.try_into().unwrap(),
                target: target.try_into().unwrap(),
                entry_chunk: entry_chunk.try_into().unwrap(),
                entry_tile: entry_tile.try_into().unwrap(),
            }
        }

        /// The zone's chunk set as the reveal reads it: its `OUTLINE`, or the whole rectangle
        /// without one.
        fn chunk_set(self: @ContractState, location: u32, frame: @Frame) -> felt252 {
            let part = self.part0(OUTLINE, location * 256 + CHUNK_SET.into());
            if part == 0 {
                OutlineTrait::rectangle(*frame.width, *frame.height)
            } else {
                part - LIVE
            }
        }

        /// How many chunks a location's quotas are placed among, but an authored zone's (its
        /// candidates): a dungeon floor's `N` (its outline, drawn at `create`), a generated zone's
        /// chunk set (`chunk_set`, `set` when given: the one being written).
        fn members(self: @ContractState, location: u32, frame: @Frame, set: Option<felt252>) -> u8 {
            if *frame.target != 0 {
                return *frame.target;
            }
            let set = match set {
                Some(bits) => bits,
                None => self.chunk_set(location, frame),
            };
            BoardTrait::count(set)
        }

        /// The six quotas' candidate sets (0 where no `CANDIDATES` part holds them).
        fn candidates(self: @ContractState, location: u32) -> Span<felt252> {
            let mut out = array![];
            self.read_into(CANDIDATES, location * 2, 3, ref out);
            self.read_into(CANDIDATES, location * 2 + 1, 3, ref out);
            let mut sets: Array<felt252> = array![];
            for part in out.span() {
                sets.append(if *part == 0 {
                    0
                } else {
                    *part - LIVE
                });
            }
            sets.span()
        }

        fn quotas(self: @ContractState, location: u32) -> Option<QuotaSet> {
            let part = self.part0(QUOTAS, location);
            if part == 0 {
                None
            } else {
                Some(QuotaSetRecord::unpack(array![part].span()))
            }
        }

        fn zone_chunk(self: @ContractState, location: u32, chunk: u8) -> Option<ZoneChunk> {
            let record = self.parts_of(ZONE_CHUNK, location * 256 + chunk.into());
            if *record[0] == 0 {
                None
            } else {
                Some(ZoneChunkRecord::unpack(record))
            }
        }

        /// A `ZONE_CHUNK`'s `Brief` (part 1's high limb: the bridges' count at 208, the gates at
        /// 212 and 228).
        fn brief(self: @ContractState, location: u32, chunk: u8) -> Option<Brief> {
            let record = self.parts_of(ZONE_CHUNK, location * 256 + chunk.into());
            if *record[0] == 0 {
                return None;
            }
            let (_, high) = split(*record[1]);
            let rest = high / 0x100000000000000000000;
            let (rest, bridges) = DivRem::div_rem(rest, 0x10);
            let (rest, g0) = DivRem::div_rem(rest, 0x10000);
            let (_, g1) = DivRem::div_rem(rest, 0x10000);
            Some(
                Brief {
                    walls: *record[0] - LIVE,
                    bridges: bridges.try_into().unwrap(),
                    gates: (g0.try_into().unwrap(), g1.try_into().unwrap()),
                },
            )
        }

        fn bridge(self: @ContractState, location: u32, chunk: u8, k: u8) -> Option<Bridge> {
            let part = self.part0(BRIDGE, location * 4096 + chunk.into() * 16 + k.into());
            if part == 0 {
                None
            } else {
                Some(BridgeRecord::unpack(array![part].span()))
            }
        }

        /// A `GATE`'s source and anchor (`(source, anchor chunk, anchor tile)`, part 0's low bits),
        /// if it exists.
        fn anchor(self: @ContractState, gate: u16) -> Option<(u32, u8, u8)> {
            let part = self.part0(GATE, gate.into());
            if part == 0 {
                return None;
            }
            let (low, _) = split(part);
            let (rest, source) = DivRem::div_rem(low, 0x10000);
            let (rest, chunk) = DivRem::div_rem(rest / 0x10000, 0x100);
            let (_, tile) = DivRem::div_rem(rest, 0x100);
            Some((source.try_into().unwrap(), chunk.try_into().unwrap(), tile.try_into().unwrap()))
        }

        /// R-12, R-13, R-27, R-29 and R-30 (`QuotaBoundsAssert::assert_bounds`) of a location's
        /// quotas, against how many `members` it has (`members`), an authored zone's `candidates`
        /// (`None` for any other location: R-12, R-27 and R-30 alone, ENG-R1c-1) and the Heart
        /// templates.
        fn assert_bounds(
            self: @ContractState, quotas: @QuotaSet, members: u8, candidates: Option<Span<felt252>>,
        ) {
            let mut hearts: Array<Option<Pack>> = array![];
            for entry in quotas.quotas.span() {
                let mut pack = None;
                if *entry.kind == quota_kind::HEART {
                    let part = self.part0(PACK, (*entry.param).into());
                    if part != 0 {
                        pack = Some(PackRecord::unpack(array![part].span()));
                    }
                }
                hearts.append(pack);
            }
            quotas.assert_bounds(members, candidates, hearts.span());
        }

        /// R-37 at chunk `chunk`: none of `tiles` on any of its `count` bridges.
        fn assert_clear(self: @ContractState, location: u32, chunk: u8, count: u8, tiles: felt252) {
            for k in 0..count {
                if let Some(bridge) = self.bridge(location, chunk, k) {
                    bridge.assert_clear(tiles);
                }
            }
        }

        /// The tiles of chunk `chunk` that bear authored content besides its own placements: the
        /// anchors of the gates it names that anchor there, and the entry when it is the entry
        /// chunk of an authored zone (R-37).
        fn anchors(self: @ContractState, location: u32, chunk: u8, gates: (u16, u16)) -> felt252 {
            let frame = self.frame(location);
            let mut tiles: felt252 = 0;
            if frame.authored && frame.entry_chunk == chunk {
                tiles = BoardTrait::pow(frame.entry_tile);
            }
            let (g0, g1) = gates;
            for gate in array![g0, g1].span() {
                if *gate != 0 {
                    if let Some((source, at, tile)) = self.anchor(*gate) {
                        if source == location && at == chunk {
                            tiles = BoardTrait::or(tiles, BoardTrait::pow(tile));
                        }
                    }
                }
            }
            tiles
        }

        /// A `LOCATION` write, against the records it shares a rule with: R-11, its stored chunk
        /// set within the rectangle (which may shrink); R-41, the entries of the gates that lead
        /// to it (`gate_entries`) within it, when it has a map; R-12, R-27 and R-30 against its
        /// stored `QUOTAS` (its members: `members`). An authored zone's, besides: R-39; R-26 and
        /// R-37 against its entry chunk's record and bridges; R-13 and R-29 with the quotas'.
        /// R-28 and R-40, on itself alone, are `Registry`'s (`LocationAssert::assert_floor`).
        fn assert_location(self: @ContractState, id: u32, location: @Location) {
            let authored = *location.target == 0 && location.authored();
            let (width, height) = (*location.width, *location.height);
            let set = self.part0(OUTLINE, id * 256 + CHUNK_SET.into());
            if set != 0 {
                OutlineAssert::assert_within(set - LIVE, width, height);
            }
            if location.has_map() {
                GateAssert::assert_entries(self.gate_entries.read(id), width, height);
            }
            if authored {
                location.assert_band();
                let chunk = *location.entry_chunk;
                let tile = *location.entry_tile;
                if let Some(brief) = self.brief(id, chunk) {
                    assert(tile < 225 && !BoardTrait::has(brief.walls, tile), chunk_errors::ENTRY);
                    self.assert_clear(id, chunk, brief.bridges, BoardTrait::pow(tile));
                }
            }
            if let Some(quotas) = self.quotas(id) {
                let members = if *location.target != 0 {
                    *location.target
                } else if set == 0 {
                    width * height
                } else {
                    BoardTrait::count(set - LIVE)
                };
                let candidates = if authored {
                    Some(self.candidates(id))
                } else {
                    None
                };
                self.assert_bounds(@quotas, members, candidates);
            }
        }

        /// An `OUTLINE` write. The chunk set: R-31 against both `CANDIDATES` and R-24 against
        /// every chunk it drops (none may hold a `ZONE_CHUNK`); R-11 within the rectangle; an
        /// authored zone's R-12, R-13 and R-30 against `QUOTAS` (its members), a generated zone's
        /// R-12 and R-30 (a dungeon floor's members are its `N`, not its chunk set). A border
        /// chunk's mask: R-20 against that chunk's `ZONE_CHUNK`.
        fn assert_outline(self: @ContractState, id: u32, bits: felt252) {
            let (location, chunk) = DivRem::div_rem(id, 256);
            if chunk != CHUNK_SET.into() {
                if chunk < INDEX_BOUND.into() {
                    let walls = self.part0(ZONE_CHUNK, id);
                    if walls != 0 {
                        ZoneChunkAssert::assert_mask(walls - LIVE, bits);
                    }
                }
                return;
            }
            let candidates = self.candidates(location);
            CandidatesAssert::assert_within(candidates, bits);
            let frame = self.frame(location);
            OutlineAssert::assert_within(bits, frame.width, frame.height);
            if frame.target == 0 {
                if let Some(quotas) = self.quotas(location) {
                    let candidates = if frame.authored {
                        Some(candidates)
                    } else {
                        None
                    };
                    self.assert_bounds(@quotas, BoardTrait::count(bits), candidates);
                }
            }
            let mut dropped = BoardTrait::minus(self.chunk_set(location, @frame), bits);
            while dropped != 0 {
                let chunk = BoardTrait::nth(dropped, 0);
                dropped -= BoardTrait::pow(chunk);
                let there = self.part0(ZONE_CHUNK, location * 256 + chunk.into());
                assert(there == 0, chunk_errors::NOT_IN_SET);
            }
        }

        /// A `QUOTAS` write: R-12, R-27 and R-30 against the location's members (`members`) and
        /// the Heart templates, whatever the location (ENG-R1c-1); an authored zone's, besides,
        /// R-13 and R-29 against `CANDIDATES`, and R-15 again on the candidate chunks of every
        /// quota whose kind changed (an object quota counts against 3 objects, a Heart against 2
        /// packs).
        fn assert_quotas(self: @ContractState, id: u32, quotas: @QuotaSet) {
            let frame = self.frame(id);
            if !frame.authored {
                self.assert_bounds(quotas, self.members(id, @frame, None), None);
                return;
            }
            let candidates = self.candidates(id);
            self.assert_bounds(quotas, self.members(id, @frame, None), Some(candidates));
            let before = self.part0(QUOTAS, id);
            let before = QuotaSetRecord::unpack(array![before].span());
            let mut changed: felt252 = 0;
            for i in 0..6_u32 {
                if *before.quotas.span()[i].kind != *quotas.quotas.span()[i].kind {
                    changed = BoardTrait::or(changed, *candidates[i]);
                }
            }
            self.assert_chunks(id, changed, candidates, quotas);
        }

        /// R-14 and R-15 on every chunk of `chunks` that holds a `ZONE_CHUNK`.
        fn assert_chunks(
            self: @ContractState,
            location: u32,
            chunks: felt252,
            candidates: Span<felt252>,
            quotas: @QuotaSet,
        ) {
            let mut left = chunks;
            while left != 0 {
                let chunk = BoardTrait::nth(left, 0);
                left -= BoardTrait::pow(chunk);
                if let Some(record) = self.zone_chunk(location, chunk) {
                    record.assert_legal(chunk, candidates, quotas);
                }
            }
        }

        /// A `CANDIDATES` write (`sets`: quotas `3 k` to `3 k + 2`): R-31 against the chunk set;
        /// R-12, R-13, R-27, R-29 and R-30 against an authored zone's `QUOTAS`; R-14 and R-15
        /// again on each chunk whose candidacy changed.
        fn assert_candidates(self: @ContractState, id: u32, sets: [felt252; 3]) {
            let (location, k) = DivRem::div_rem(id, 2);
            let frame = self.frame(location);
            if !frame.exists {
                return;
            }
            let [s0, s1, s2] = sets;
            let mut candidates: Array<felt252> = array![];
            let mut changed: felt252 = 0;
            let mut i: u32 = 0;
            for old in self.candidates(location) {
                let new = if i / 3 != k {
                    *old
                } else if i % 3 == 0 {
                    s0
                } else if i % 3 == 1 {
                    s1
                } else {
                    s2
                };
                let both = BoardTrait::and(*old, new);
                changed =
                    BoardTrait::or(changed, BoardTrait::minus(BoardTrait::or(*old, new), both));
                candidates.append(new);
                i += 1;
            }
            let candidates = candidates.span();
            let members = self.chunk_set(location, @frame);
            CandidatesAssert::assert_within(array![s0, s1, s2].span(), members);
            let part = self.part0(QUOTAS, location);
            let quotas = QuotaSetRecord::unpack(array![part].span());
            if part != 0 && frame.authored {
                self.assert_bounds(@quotas, BoardTrait::count(members), Some(candidates));
            }
            self.assert_chunks(location, changed, candidates, @quotas);
        }

        /// A `ZONE_CHUNK` write: R-24 (in the chunk set), R-20 (its mask), R-14 and R-15 (its
        /// placements, against `CANDIDATES` and `QUOTAS`), R-26 (the entry chunk of an authored
        /// zone); R-18 again for each gate it names that anchors here, and R-25: a gate it no
        /// longer names may not anchor here; R-35: its count may not drop below a written
        /// `BRIDGE`; R-34 and R-37 again for each of its bridges.
        fn assert_zone_chunk(self: @ContractState, id: u32, record: @ZoneChunk) {
            let (location, chunk) = DivRem::div_rem(id, 256);
            let frame = self.frame(location);
            if !frame.exists || chunk >= INDEX_BOUND.into() {
                return;
            }
            let chunk: u8 = chunk.try_into().unwrap();
            let mask = self.part0(OUTLINE, id);
            let mask = if mask == 0 {
                0
            } else {
                mask - LIVE
            };
            record.assert_outline(chunk, self.chunk_set(location, @frame), mask);
            let quotas = QuotaSetRecord::unpack(array![self.part0(QUOTAS, location)].span());
            record.assert_legal(chunk, self.candidates(location), @quotas);
            if frame.authored && frame.entry_chunk == chunk {
                record.assert_entry(frame.entry_tile);
            }
            // The gates: those it names anchored on its floor, none it drops anchored here
            for gate in record.gates.span() {
                if *gate != 0 {
                    if let Some((source, at, tile)) = self.anchor(*gate) {
                        if source == location && at == chunk {
                            record.assert_gate(*gate, tile);
                        }
                    }
                }
            }
            let (count, g0, g1) = match self.brief(location, chunk) {
                Some(old) => {
                    let (g0, g1) = old.gates;
                    (old.bridges, g0, g1)
                },
                None => (0, 0, 0),
            };
            for gate in array![g0, g1].span() {
                if *gate != 0 && !record.names(*gate) {
                    if let Some((source, at, _)) = self.anchor(*gate) {
                        assert(source != location || at != chunk, chunk_errors::GATE_INDEX);
                    }
                }
            }
            // The bridges: none past the new count, each below it still on floor and clear
            let mut k = *record.bridges;
            while k < count {
                assert(self.part0(BRIDGE, id * 16 + k.into()) == 0, bridge_errors::INDEX);
                k += 1;
            }
            let [n0, n1] = *record.gates;
            let anchors = self.anchors(location, chunk, (n0, n1));
            let odd = (chunk / 15) % 2 == 1;
            for k in 0..*record.bridges {
                if let Some(bridge) = self.bridge(location, chunk, k) {
                    bridge.assert_on(k, record, odd);
                    bridge.assert_clear(anchors);
                }
            }
        }

        /// A `BRIDGE` write: R-33 (a deck, two distinct ends off it); against its chunk's
        /// `ZONE_CHUNK` (none: no bridge, R-35), R-35, R-34 extended to the deck and R-37, the
        /// gates anchored there and the entry included.
        fn assert_bridge(self: @ContractState, id: u32, bridge: @Bridge) {
            bridge.assert_legal();
            let (location, rest) = DivRem::div_rem(id, 4096);
            let (chunk, k) = DivRem::div_rem(rest, 16);
            if chunk >= INDEX_BOUND.into() {
                return;
            }
            let chunk: u8 = chunk.try_into().unwrap();
            let Some(record) = self.zone_chunk(location, chunk) else {
                core::panic_with_felt252(bridge_errors::INDEX)
            };
            bridge.assert_on(k.try_into().unwrap(), @record, (chunk / 15) % 2 == 1);
            let [g0, g1] = record.gates;
            bridge.assert_clear(self.anchors(location, chunk, (g0, g1)));
        }

        /// A `GATE` write: R-43, its chunks and tiles on the board; R-41, its entry within its
        /// destination's rectangle when the destination exists and has a map (a later `LOCATION`
        /// write checks it the other way, `gate_entries`); anchored in a chunk that holds a
        /// `ZONE_CHUNK`, R-18 (the anchor walkable), R-25 (the chunk names the gate) and R-37 (not
        /// on a bridge).
        fn assert_gate(self: @ContractState, id: u32, record: Span<felt252>) {
            let gate = GateRecord::unpack(record);
            // R-43 (BND-01): the record's own bounds, whatever the destination (R-41 reads the
            // entry only against a destination with a map); `unpack` does not check them
            gate.assert_valid();
            let destination = self.frame(gate.destination.into());
            if destination.map {
                gate.assert_entry(destination.width, destination.height);
            }
            let location: u32 = gate.source.into();
            let Some(brief) = self.brief(location, gate.anchor_chunk) else {
                return;
            };
            let tile = gate.anchor_tile;
            assert(tile < 225 && !BoardTrait::has(brief.walls, tile), chunk_errors::GATE_ANCHOR);
            let (g0, g1) = brief.gates;
            let id: u16 = id.try_into().unwrap();
            assert(g0 == id || g1 == id, chunk_errors::GATE_INDEX);
            self.assert_clear(location, gate.anchor_chunk, brief.bridges, BoardTrait::pow(tile));
        }
    }


    #[generate_trait]
    impl ReadImpl of ReadTrait {
        /// Appends the `count` parts of `(kind, id)` to `out` (`Registry`'s `records`).
        fn read_into(self: @ContractState, kind: u8, id: u32, count: u8, ref out: Array<felt252>) {
            for part in 0..count {
                out.append(self.records.read((kind, id, part)));
            }
        }
    }
}
