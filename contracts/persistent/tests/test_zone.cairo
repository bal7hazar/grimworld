// ENG-09: the Registry's content checks of an authored zone's records (ENG-01 §3.5's R-table,
// ENG-08's format). The sample zone (`tools/map-format/samples/zone.json`, the converter's
// `zone.golden.json`) is written through `set_record` in the converter's order and passes every
// check; each registry case of `tools/map-format/checks.json` is a write, or a rewrite, of that
// sample which breaks the same rule, refused with the same code as the converter refuses it
// (`tools/map-format/tests/test_convert.py`, which holds that each `test_refuse_<case>` exists
// here with its code). A rule between two records is refused at the write of either: the reverse
// checks are tested from the other side.
use grimworld_logic::content::{
    BRIDGE, CANDIDATES, GATE, LOCATION, OUTLINE, PACK, QUOTAS, Record, ZONE_CHUNK,
};
use grimworld_logic::interface::{
    IHostsLibraryDispatcherTrait, IHostsLibraryLibraryDispatcher, IRegistryReadDispatcher,
    IRegistryReadDispatcherTrait,
};
use grimworld_logic::models::bridge::{Bridge, BridgeRecord};
use grimworld_logic::models::candidates::{Candidates, CandidatesRecord};
use grimworld_logic::models::chunk::{Object, object};
use grimworld_logic::models::gate::{Gate, GateRecord};
use grimworld_logic::models::location::{
    Location, LocationAssert, LocationRecord, LocationTrait, kind as location_kind, map,
};
use grimworld_logic::models::outline::{OutlineRecord, OutlineTrait};
use grimworld_logic::models::pack::{Pack, PackCaste, PackRecord};
use grimworld_logic::models::quotas::{Quota, QuotaSet, QuotaSetRecord, kind as quota_kind};
use grimworld_logic::models::zone_chunk::{ZoneChunk, ZoneChunkRecord, ZoneChunkTrait};
use grimworld_logic::packing::{LIVE, Lanes16};
use grimworld_logic::types::reveal::Progress;
use grimworld_logic::types::reveal::board::BoardTrait;
use grimworld_persistent::systems::registry::{
    IRegistryAdminDispatcher, IRegistryAdminDispatcherTrait, IRegistryAdminSafeDispatcher,
    IRegistryAdminSafeDispatcherTrait,
};
use snforge_std::fs::{FileTrait, read_json};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address};
use starknet::{ClassHash, ContractAddress};

const ADMIN: felt252 = 0xad;
/// The sample zone's location id (the manifest's `meadow_edge`).
const ZONE: u32 = 2;

#[derive(Copy, Drop)]
struct Registry {
    address: ContractAddress,
    admin: IRegistryAdminDispatcher,
    safe: IRegistryAdminSafeDispatcher,
    read: IRegistryReadDispatcher,
}

/// One record of the sample, as the converter packed it.
#[derive(Drop, Copy)]
struct Write {
    kind: u8,
    id: u32,
    parts: Span<felt252>,
}

fn felt(ref stream: Span<felt252>) -> felt252 {
    let mut out: u256 = 0;
    let mut factor: u256 = 1;
    for i in 0..8_u8 {
        let limb: u256 = (*stream.pop_front().unwrap()).into();
        out += limb * factor;
        if i != 7 {
            factor *= 0x100000000;
        }
    }
    out.try_into().unwrap()
}

/// The sample's records in the converter's order (`convert.py`'s `zone_writes`): snforge's
/// `read_json` gives `chunk_count`, then `chunk_fields`, `chunk_parts` and `records`, each array
/// after its length; a felt is 8 limbs of 32 bits. The `ZONE_CHUNK`s go before the first
/// `BRIDGE` or `GATE`, as the converter writes them.
fn sample() -> Array<Write> {
    let file = FileTrait::new("../../tools/map-format/samples/zone.golden.json");
    let felts = read_json(@file);
    let mut stream = felts.span();
    let count: u32 = (*stream.pop_front().unwrap()).try_into().unwrap();
    let fields: u32 = (*stream.pop_front().unwrap()).try_into().unwrap();
    for _ in 0..fields {
        stream.pop_front().unwrap();
    }
    let _length = stream.pop_front();
    let mut chunks: Array<Write> = array![];
    for _ in 0..count {
        let chunk: u32 = (*stream.pop_front().unwrap()).try_into().unwrap();
        let parts = array![felt(ref stream), felt(ref stream)].span();
        chunks.append(Write { kind: ZONE_CHUNK, id: ZONE * 256 + chunk, parts });
    }
    let length: u32 = (*stream.pop_front().unwrap()).try_into().unwrap();
    let mut out: Array<Write> = array![];
    let mut flushed = false;
    let mut kind: u8 = 0;
    let mut id: u32 = 0;
    let mut parts: Array<felt252> = array![];
    for _ in 0..length / 10 {
        let k: u8 = (*stream.pop_front().unwrap()).try_into().unwrap();
        let i: u32 = (*stream.pop_front().unwrap()).try_into().unwrap();
        let part = felt(ref stream);
        if (k != kind || i != id) && parts.len() != 0 {
            out.append(Write { kind, id, parts: parts.span() });
            parts = array![];
        }
        if !flushed && (k == BRIDGE || k == GATE) {
            for chunk in chunks.span() {
                out.append(*chunk);
            }
            flushed = true;
        }
        kind = k;
        id = i;
        parts.append(part);
    }
    out.append(Write { kind, id, parts: parts.span() });
    out
}

/// The raiders (2 to 5 goblins) and the cubs, the manifest's two templates (`contracts/seed`'s).
fn raiders() -> Pack {
    Pack {
        castes: [
            PackCaste { caste: 1, min: 1, max: 2 }, PackCaste { caste: 2, min: 1, max: 3 },
            Default::default(), Default::default(), Default::default(),
        ],
        level: 0,
    }
}

fn cubs() -> Pack {
    Pack {
        castes: [
            PackCaste { caste: 3, min: 1, max: 1 }, PackCaste { caste: 1, min: 0, max: 2 },
            Default::default(), Default::default(), Default::default(),
        ],
        level: 1,
    }
}

/// A location of `kind` with no map but its size (the town, the dungeon floor the gates reach).
fn plain(kind: u8, width: u8, height: u8, target: u8) -> Location {
    LocationTrait::new(
        kind,
        1,
        1,
        1,
        3,
        0,
        width,
        height,
        target,
        0,
        0,
        0,
        false,
        0,
        0,
        Lanes16 { lanes: [0; 15] },
    )
}

#[generate_trait]
impl ZoneFixture of Fixture {
    /// A registry deployed with `ADMIN`, the caller `ADMIN`, its zone checks set (`ZoneChecks`);
    /// the town (1), the two templates, a
    /// first gate (1, so that the sample's are 2 and 3), then the sample: its `LOCATION` (2) and
    /// every record in the converter's order; then, before the gates, the 15 × 15 dungeon floor of
    /// `N` 6 its gate 3 enters at chunk 112 (3, the seed's floor 1).
    fn deploy() -> Registry {
        let r = Self::bare();
        let first = Gate {
            source: 1,
            destination: 1,
            anchor_chunk: 0,
            anchor_tile: 0,
            entry_chunk: 0,
            entry_tile: 0,
            kind: 1,
            rank: 0,
            quest: 0,
        };
        r.admin.set_record(GATE, 1, first.pack());
        let mut floor_written = false;
        for write in sample() {
            if write.kind == GATE && !floor_written {
                r.admin.set_record(LOCATION, 3, plain(location_kind::DUNGEON, 15, 15, 6).pack());
                floor_written = true;
            }
            r.admin.set_record(write.kind, write.id, write.parts);
        }
        r
    }

    /// The registry of `deploy` before its first gate and the sample: its zone checks, the town
    /// (1) and the two templates. The next location is 2, the next gate 1.
    fn bare() -> Registry {
        let contract = declare("Registry").unwrap().contract_class();
        let (address, _) = contract.deploy(@array![ADMIN]).unwrap();
        start_cheat_caller_address(address, ADMIN.try_into().unwrap());
        let r = Registry {
            address,
            admin: IRegistryAdminDispatcher { contract_address: address },
            safe: IRegistryAdminSafeDispatcher { contract_address: address },
            read: IRegistryReadDispatcher { contract_address: address },
        };
        r.admin.set_zone_checks(class("ZoneChecks"));
        r.admin.set_record(LOCATION, 1, plain(location_kind::TOWN, 0, 0, 0).pack());
        r.admin.set_record(PACK, 1, raiders().pack());
        r.admin.set_record(PACK, 2, cubs().pack());
        r
    }

    fn parts(self: Registry, kind: u8, id: u32) -> Span<felt252> {
        self.read.record(kind, id)
    }

    fn location(self: Registry) -> Location {
        LocationRecord::unpack(self.parts(LOCATION, ZONE))
    }

    fn chunk(self: Registry, chunk: u8) -> ZoneChunk {
        ZoneChunkRecord::unpack(self.parts(ZONE_CHUNK, ZONE * 256 + chunk.into()))
    }

    fn quotas(self: Registry) -> QuotaSet {
        QuotaSetRecord::unpack(self.parts(QUOTAS, ZONE))
    }

    fn candidates(self: Registry) -> [felt252; 3] {
        CandidatesRecord::unpack(self.parts(CANDIDATES, ZONE * 2)).sets
    }

    fn bridge(self: Registry) -> Bridge {
        BridgeRecord::unpack(self.parts(BRIDGE, ZONE * 4096 + 15 * 16))
    }

    fn gate(self: Registry, id: u32) -> Gate {
        GateRecord::unpack(self.parts(GATE, id))
    }

    fn chunk_set(self: Registry) -> felt252 {
        OutlineRecord::unpack(self.parts(OUTLINE, ZONE * 256 + 255)).bits()
    }

    /// The write, which must be refused: the test panics with the refusal's code.
    #[feature("safe_dispatcher")]
    fn refuse(self: Registry, kind: u8, id: u32, record: Span<felt252>) {
        match self.safe.set_record(kind, id, record) {
            Ok(()) => core::panic_with_felt252('not refused'),
            Err(data) => core::panic_with_felt252(*data.at(0)),
        }
    }

    /// The write, which must be refused with `code`; the test goes on.
    #[feature("safe_dispatcher")]
    fn refused(self: Registry, kind: u8, id: u32, record: Span<felt252>, code: felt252) {
        match self.safe.set_record(kind, id, record) {
            Ok(()) => core::panic_with_felt252('not refused'),
            Err(data) => assert(*data.at(0) == code, *data.at(0)),
        }
    }

    fn rewrite_chunk(self: Registry, chunk: u8, record: ZoneChunk) {
        self.refuse(ZONE_CHUNK, ZONE * 256 + chunk.into(), record.pack());
    }

    fn rewrite_quota(self: Registry, i: u32, quota: Quota) {
        let mut quotas: Array<Quota> = array![];
        let mut j: u32 = 0;
        for entry in self.quotas().quotas.span() {
            quotas.append(if j == i {
                quota
            } else {
                *entry
            });
            j += 1;
        }
        let set = QuotaSet {
            quotas: [*quotas[0], *quotas[1], *quotas[2], *quotas[3], *quotas[4], *quotas[5]],
        };
        self.refuse(QUOTAS, ZONE, set.pack());
    }

    fn rewrite_candidates(self: Registry, sets: [felt252; 3]) {
        self.refuse(CANDIDATES, ZONE * 2, Candidates { sets }.pack());
    }

    fn rewrite_bridge(self: Registry, bridge: Bridge) {
        self.refuse(BRIDGE, ZONE * 4096 + 15 * 16, bridge.pack());
    }
}

fn first_wall(record: @ZoneChunk) -> u8 {
    BoardTrait::nth(*record.walls, 0)
}

fn first_floor(record: @ZoneChunk) -> u8 {
    BoardTrait::nth(
        BoardTrait::minus(
            0x1ffffffffffffffffffffffffffffffffffffffffffffffffffffffff, *record.walls,
        ),
        0,
    )
}

// --- The sample passes ---------------------------------------------------------------------------

#[test]
#[available_gas(l2_gas: 59892149)] // ceil(1.05 × 57040141 measured)
fn test_sample_registered() {
    let r = ZoneFixture::deploy();
    let location = r.location();
    assert(location.map == map::AUTHORED && location.authored(), 'the marker');
    assert(r.chunk_set() == 0x18007, 'the chunk set');
    for write in sample() {
        assert(r.parts(write.kind, write.id) == write.parts, 'stored as packed');
    }
}

// R-27's index binds every location's Heart quotas (ENG-R1c-1; an authored zone's alone before):
// the sample's Heart names the raiders (1); the marker dropped, they stay bound; a `QUOTAS` rewrite
// without the Heart frees them, one that names them again binds them (`heart_packs`).
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 60245469)] // ceil(1.05 × 57376637 measured)
fn test_heart_index_binds_every_location() {
    let r = ZoneFixture::deploy();
    let empty = Pack {
        castes: [
            PackCaste { caste: 1, min: 0, max: 2 }, PackCaste { caste: 2, min: 0, max: 3 },
            Default::default(), Default::default(), Default::default(),
        ],
        level: 0,
    };
    let generated = r.location().with_map(map::GENERATED);
    r.admin.set_record(LOCATION, ZONE, generated.pack());
    r.refused(PACK, 1, empty.pack(), 'zone: heart template');
    let quotas = r.quotas();
    let [q0, q1, heart, q3, q4, q5] = quotas.quotas;
    assert(heart.kind == quota_kind::HEART && heart.param == 1, 'quota 2 the raiders');
    let without = QuotaSet { quotas: [q0, q1, Default::default(), q3, q4, q5] };
    r.admin.set_record(QUOTAS, ZONE, without.pack());
    // Freed, the raiders are bound by R-42 alone (BND-01): another code, not R-27's
    r.refused(PACK, 1, empty.pack(), 'pack: fewest is 0');
    r.admin.set_record(PACK, 1, raiders().pack());
    r.admin.set_record(QUOTAS, ZONE, quotas.pack());
    r.refused(PACK, 1, empty.pack(), 'zone: heart template');
}

// --- The authored reveal on the real path: `HostsLibrary` reading `Registry` ---------------------

fn class(name: ByteArray) -> ClassHash {
    *declare(name).unwrap().contract_class().class_hash
}

/// The words of `chunk` among `words`.
fn words_of(words: Span<(u8, felt252, felt252)>, chunk: u8) -> (felt252, felt252) {
    let mut found: (felt252, felt252) = (0, 0);
    for entry in words {
        let (at, terrain, features) = *entry;
        if at == chunk {
            found = (terrain, features);
        }
    }
    found
}

// `create`'s entry reveal (`enter`: the hosts drawn once among the candidates, the entry chunk
// copied), then the four other chunks revealed in play (`reveal`, the stored hosts) in two orders:
// the same words and the same progress (D-208, ENG-08's ruling 3 and 4); every quota placed; each
// chunk's plane the record's; nothing generated (no outline drawn).
#[test]
#[available_gas(l2_gas: 109382461)] // ceil(1.05 × 104173772 measured)
fn test_authored_reveal_through_hosts_library() {
    let r = ZoneFixture::deploy();
    let reveal = class("RevealLibrary");
    let library = IHostsLibraryLibraryDispatcher { class_hash: class("HostsLibrary") };
    let location = r.location();
    let mut entropy: felt252 = 0x5eed;
    for _ in 0..3_u8 {
        let (progress, entered, hosts, outline) = library
            .enter(
                r.address,
                reveal,
                ZONE.try_into().unwrap(),
                location,
                location.entry_chunk,
                location.entry_tile,
                array![].span(),
                array![0].span(),
                entropy,
                7,
            );
        assert(outline.is_none() && entered.len() == 1 && hosts.len() == 6, 'entered');
        let (terrain, _) = words_of(entered, 0);
        assert(terrain == r.chunk(0).walls + LIVE, 'plane copied');
        let rest = array![1, 2, 15, 16].span();
        let back = array![16, 15, 2, 1].span();
        let (a, wa) = library
            .reveal(
                r.address,
                reveal,
                ZONE.try_into().unwrap(),
                location,
                location.entry_chunk,
                location.entry_tile,
                array![].span(),
                hosts,
                None,
                progress,
                7,
                array![].span(),
                rest,
            );
        let (b, wb) = library
            .reveal(
                r.address,
                reveal,
                ZONE.try_into().unwrap(),
                location,
                location.entry_chunk,
                location.entry_tile,
                array![].span(),
                hosts,
                None,
                progress,
                7,
                array![].span(),
                back,
            );
        assert(a == b && a.count == 5 && a.revealed == r.chunk_set(), 'progress');
        for chunk in rest {
            assert(words_of(wa, *chunk) == words_of(wb, *chunk), 'order-free');
            let (terrain, _) = words_of(wa, *chunk);
            assert(terrain == r.chunk(*chunk).walls + LIVE, 'plane copied');
        }
        for i in 0..6_u32 {
            assert(*a.left.span()[i] == 0, 'every quota placed');
        }
        entropy = entropy * 31 + 7;
    }
}

// Play reveals one segment a call (audit t-0131, minor 2): the four other chunks revealed one per
// call, each call's progress passed to the next, in two orders, give the same words per chunk and
// the same final progress.
#[test]
#[available_gas(l2_gas: 75420653)] // ceil(1.05 × 71829193 measured)
fn test_authored_reveal_threaded() {
    let r = ZoneFixture::deploy();
    let reveal = class("RevealLibrary");
    let library = IHostsLibraryLibraryDispatcher { class_hash: class("HostsLibrary") };
    let location = r.location();
    let zone: u16 = ZONE.try_into().unwrap();
    let (entered, _, hosts, _) = library
        .enter(
            r.address,
            reveal,
            zone,
            location,
            location.entry_chunk,
            location.entry_tile,
            array![].span(),
            array![0].span(),
            0xfeed,
            7,
        );
    let mut results: Array<(Progress, Array<(u8, felt252, felt252)>)> = array![];
    for order in array![array![1_u8, 2, 15, 16].span(), array![16_u8, 15, 2, 1].span()].span() {
        let mut progress = entered;
        let mut words: Array<(u8, felt252, felt252)> = array![];
        for chunk in *order {
            let (next, out) = library
                .reveal(
                    r.address,
                    reveal,
                    zone,
                    location,
                    location.entry_chunk,
                    location.entry_tile,
                    array![].span(),
                    hosts,
                    None,
                    progress,
                    7,
                    array![].span(),
                    array![*chunk].span(),
                );
            assert(out.len() == 1, 'one chunk a call');
            words.append(*out[0]);
            progress = next;
        }
        results.append((progress, words));
    }
    let (a, wa) = results.pop_front().unwrap();
    let (b, wb) = results.pop_front().unwrap();
    assert(a == b && a.count == 5, 'final progress');
    for chunk in array![1_u8, 2, 15, 16].span() {
        assert(words_of(wa.span(), *chunk) == words_of(wb.span(), *chunk), 'words per chunk');
    }
}

// --- The zone checks' class
// ------------------------------------------------------------------------

// Before `set_zone_checks`, an authored zone's records are refused: none can exist unchecked.
#[test]
#[available_gas(l2_gas: 4247691)] // ceil(1.05 × 4045420 measured)
#[should_panic(expected: 'registry: no zone checks')]
fn test_refuse_without_zone_checks() {
    let contract = declare("Registry").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![ADMIN]).unwrap();
    start_cheat_caller_address(address, ADMIN.try_into().unwrap());
    let r = Registry {
        address,
        admin: IRegistryAdminDispatcher { contract_address: address },
        safe: IRegistryAdminSafeDispatcher { contract_address: address },
        read: IRegistryReadDispatcher { contract_address: address },
    };
    r.admin.set_record(LOCATION, 1, plain(location_kind::TOWN, 0, 0, 0).pack());
    let zone = plain(location_kind::ZONE, 1, 1, 0).with_map(map::AUTHORED);
    r.refuse(LOCATION, 2, zone.pack());
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 52672380)] // ceil(1.05 × 50164171 measured)
#[should_panic(expected: 'registry: zone checks zero')]
#[feature("safe_dispatcher")]
fn test_refuse_zone_checks_zero() {
    let r = ZoneFixture::deploy();
    match r.safe.set_zone_checks(0.try_into().unwrap()) {
        Ok(()) => core::panic_with_felt252('not refused'),
        Err(data) => core::panic_with_felt252(*data.at(0)),
    }
}

// `set_zone_checks` is the administrator's (D-245): another caller is refused and nothing changes
// (an authored zone's record still refused); the administrator's call takes effect (the same record
// accepted).
#[test]
#[available_gas(l2_gas: 7359677)] // ceil(1.05 × 7009216 measured)
#[feature("safe_dispatcher")]
fn test_set_zone_checks_admin_only() {
    let contract = declare("Registry").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![ADMIN]).unwrap();
    let r = Registry {
        address,
        admin: IRegistryAdminDispatcher { contract_address: address },
        safe: IRegistryAdminSafeDispatcher { contract_address: address },
        read: IRegistryReadDispatcher { contract_address: address },
    };
    let checks = class("ZoneChecks");
    start_cheat_caller_address(address, 0xbad.try_into().unwrap());
    match r.safe.set_zone_checks(checks) {
        Ok(()) => core::panic_with_felt252('not refused'),
        Err(data) => assert(*data.at(0) == 'not admin', 'not admin'),
    }
    start_cheat_caller_address(address, ADMIN.try_into().unwrap());
    r.admin.set_record(LOCATION, 1, plain(location_kind::TOWN, 0, 0, 0).pack());
    let zone = plain(location_kind::ZONE, 1, 1, 0).with_map(map::AUTHORED).pack();
    match r.safe.set_record(LOCATION, 2, zone) {
        Ok(()) => core::panic_with_felt252('accepted unchecked'),
        Err(data) => assert(*data.at(0) == 'registry: no zone checks', 'still unset'),
    }
    r.admin.set_zone_checks(checks);
    r.admin.set_record(LOCATION, 2, zone);
    assert(r.read.record(LOCATION, 2) == zone, 'checked and written');
}

// --- Each case of `checks.json`'s registry table -------------------------------------------------

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 53731952)] // ceil(1.05 × 51173287 measured)
#[should_panic(expected: 'zone: set outside rectangle')]
fn test_refuse_set_outside() {
    let r = ZoneFixture::deploy();
    r.refuse(OUTLINE, ZONE * 256 + 255, OutlineRecord::pack(@OutlineTrait::new(0x18007 + 8, 0)));
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54299248)] // ceil(1.05 × 51713569 measured)
#[should_panic(expected: 'zone: count above members')]
fn test_refuse_count_above_members() {
    let r = ZoneFixture::deploy();
    r.rewrite_quota(0, Quota { kind: quota_kind::COLLECTOR, param: 1, count: 6 });
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54332457)] // ceil(1.05 × 51745197 measured)
#[should_panic(expected: 'zone: count above candidates')]
fn test_refuse_count_above_candidates() {
    let r = ZoneFixture::deploy();
    r.rewrite_quota(0, Quota { kind: quota_kind::COLLECTOR, param: 1, count: 3 });
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54475227)] // ceil(1.05 × 51881168 measured)
#[should_panic(expected: 'zone chunk: tile not floor')]
fn test_refuse_spawn_on_wall() {
    let r = ZoneFixture::deploy();
    let record = r.chunk(1);
    let [s0, s1] = record.spawns;
    let s0 = grimworld_logic::models::set_piece::SetPack { tile: first_wall(@record), ..s0 };
    r.rewrite_chunk(1, ZoneChunk { spawns: [s0, s1], ..record });
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54457141)] // ceil(1.05 × 51863943 measured)
#[should_panic(expected: 'zone chunk: tile not floor')]
fn test_refuse_spawn_on_ring() {
    let r = ZoneFixture::deploy();
    let record = r.chunk(1);
    // Tile 15 (row 1, column 0): floor, on the ring
    assert(!BoardTrait::has(record.walls, 15), 'ring tile 15 floor');
    let [s0, s1] = record.spawns;
    let s0 = grimworld_logic::models::set_piece::SetPack { tile: 15, ..s0 };
    r.rewrite_chunk(1, ZoneChunk { spawns: [s0, s1], ..record });
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54441878)] // ceil(1.05 × 51849407 measured)
#[should_panic(expected: 'zone chunk: object')]
fn test_refuse_object_kind() {
    let r = ZoneFixture::deploy();
    let record = r.chunk(0);
    let [o0, o1, o2] = record.objects;
    assert(o0.kind == object::LANDMARK, 'the landmark');
    let o0 = Object { kind: object::VEIN, ..o0 };
    r.rewrite_chunk(0, ZoneChunk { objects: [o0, o1, o2], ..record });
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54623711)] // ceil(1.05 × 52022581 measured)
#[should_panic(expected: 'zone chunk: empty with a value')]
fn test_refuse_empty_with_value() {
    let r = ZoneFixture::deploy();
    let record = r.chunk(0);
    let [t0, _, t2, t3, t4, t5] = record.tiles;
    r.rewrite_chunk(0, ZoneChunk { tiles: [t0, 5, t2, t3, t4, t5], ..record });
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54561830)] // ceil(1.05 × 51963647 measured)
#[should_panic(expected: 'zone chunk: tile taken')]
fn test_refuse_tile_taken() {
    let r = ZoneFixture::deploy();
    let record = r.chunk(2);
    let [o0, o1, o2] = record.objects;
    assert(o0.kind == object::CHEST, 'the chest');
    let [s0, _] = record.spawns;
    let o0 = Object { tile: s0.tile, ..o0 };
    r.rewrite_chunk(2, ZoneChunk { objects: [o0, o1, o2], ..record });
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 55147341)] // ceil(1.05 × 52521277 measured)
#[should_panic(expected: 'zone chunk: over its caps')]
fn test_refuse_over_caps() {
    let r = ZoneFixture::deploy();
    let record = r.chunk(2);
    let [o0, _, _] = record.objects;
    // Two more chests on free floor of the interior (rows 1 to 13, the mask's)
    let taken: felt252 = record.content();
    let mut free: Array<u8> = array![];
    let mut tile: u8 = 16;
    while free.len() != 2 {
        let (row, column) = DivRem::div_rem(tile, 15);
        if row > 0
            && row < 14
            && column > 0
            && column < 14
            && !BoardTrait::has(record.walls, tile)
            && !BoardTrait::has(taken, tile) {
            free.append(tile);
        }
        tile += 1;
    }
    let chest = Object { tile: 0, kind: object::CHEST, state: 0, param: 0 };
    let o1 = Object { tile: *free[0], ..chest };
    let o2 = Object { tile: *free[1], ..chest };
    r.rewrite_chunk(2, ZoneChunk { objects: [o0, o1, o2], ..record });
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54134648)] // ceil(1.05 × 51556807 measured)
#[should_panic(expected: 'zone: gate anchor not floor')]
fn test_refuse_gate_anchor_not_floor() {
    let r = ZoneFixture::deploy();
    let gate = Gate { anchor_tile: first_wall(@r.chunk(16)), ..r.gate(3) };
    r.refuse(GATE, 3, gate.pack());
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54136701)] // ceil(1.05 × 51558762 measured)
#[should_panic(expected: 'zone: mask disagrees')]
fn test_refuse_mask_disagrees() {
    let r = ZoneFixture::deploy();
    let record = r.chunk(2);
    assert(BoardTrait::has(record.walls, 14), 'tile 14 wall');
    r.rewrite_chunk(2, ZoneChunk { walls: record.walls - BoardTrait::pow(14), ..record });
}

// The reverse direction: the chunk set rewritten without chunk 0, which holds a `ZONE_CHUNK`.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54165982)] // ceil(1.05 × 51586649 measured)
#[should_panic(expected: 'zone: chunk not in the set')]
fn test_refuse_chunk_not_in_set() {
    let r = ZoneFixture::deploy();
    r.refuse(OUTLINE, ZONE * 256 + 255, OutlineRecord::pack(@OutlineTrait::new(0x18007 - 1, 0)));
}

// R-24 forward: a `ZONE_CHUNK` for chunk 17, inside the rectangle, outside the set.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54117125)] // ceil(1.05 × 51540119 measured)
#[should_panic(expected: 'zone: chunk not in the set')]
fn test_refuse_chunk_outside_the_set() {
    let r = ZoneFixture::deploy();
    r.rewrite_chunk(17, ZoneChunk { gates: [0, 0], bridges: 0, ..r.chunk(1) });
}

// R-25's reverse check: chunk 16 drops gate 3, which anchors there.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54999084)] // ceil(1.05 × 52380080 measured)
#[should_panic(expected: 'zone: gate not indexed')]
fn test_refuse_gate_not_indexed() {
    let r = ZoneFixture::deploy();
    r.rewrite_chunk(16, ZoneChunk { gates: [0, 0], ..r.chunk(16) });
}

// R-25 forward: a gate anchored in chunk 16, which does not name it.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 53796792)] // ceil(1.05 × 51235040 measured)
#[should_panic(expected: 'zone: gate not indexed')]
fn test_refuse_gate_unnamed() {
    let r = ZoneFixture::deploy();
    r.refuse(GATE, 4, r.gate(3).pack());
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54541635)] // ceil(1.05 × 51944414 measured)
#[should_panic(expected: 'zone: entry not floor')]
fn test_refuse_entry_not_floor() {
    let r = ZoneFixture::deploy();
    let location = Location { entry_tile: first_wall(@r.chunk(0)), ..r.location() };
    r.refuse(LOCATION, ZONE, location.pack());
}

// R-39 (audit t-0131): an authored zone's band of 0 to 255, 256 levels, which a byte's bound cannot
// draw.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54260036)] // ceil(1.05 × 51676224 measured)
#[should_panic(expected: 'zone: level band')]
fn test_refuse_level_band() {
    let r = ZoneFixture::deploy();
    let location = Location { level_min: 0, level_max: 255, ..r.location() };
    r.refuse(LOCATION, ZONE, location.pack());
}

// R-13's reverse check (review t-0084, minor 1): quota 0's count raised to its 2 candidates, then
// its candidates cut to one.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 56869262)] // ceil(1.05 × 54161201 measured)
#[should_panic(expected: 'zone: count above candidates')]
fn test_refuse_candidates_rewrite_count() {
    let r = ZoneFixture::deploy();
    let mut quotas = r.quotas();
    let [q0, q1, q2, q3, q4, q5] = quotas.quotas;
    quotas.quotas = [Quota { count: 2, ..q0 }, q1, q2, q3, q4, q5];
    r.admin.set_record(QUOTAS, ZONE, quotas.pack());
    let [_, c1, c2] = r.candidates();
    r.rewrite_candidates([BoardTrait::pow(16), c1, c2]);
}

// R-14's reverse check: chunk 1 left out of quota 0's candidates keeps its candidate tile.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54913737)] // ceil(1.05 × 52298797 measured)
#[should_panic(expected: 'zone chunk: empty with a value')]
fn test_refuse_candidates_rewrite_tile() {
    let r = ZoneFixture::deploy();
    let [c0, c1, c2] = r.candidates();
    assert(BoardTrait::has(c0, 1), 'chunk 1 a candidate');
    r.rewrite_candidates([c0 - BoardTrait::pow(1), c1, c2]);
}

// R-27's reverse check: the raiders, which the Heart quota names, rewritten empty at their fewest.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 53189778)] // ceil(1.05 × 50656931 measured)
#[should_panic(expected: 'zone: heart template')]
fn test_refuse_pack_rewrite_heart() {
    let r = ZoneFixture::deploy();
    let pack = Pack {
        castes: [
            PackCaste { caste: 1, min: 0, max: 2 }, PackCaste { caste: 2, min: 0, max: 3 },
            Default::default(), Default::default(), Default::default(),
        ],
        level: 0,
    };
    r.refuse(PACK, 1, pack.pack());
}

// R-27 forward: a Heart naming a template the registry does not hold.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54543881)] // ceil(1.05 × 51946553 measured)
#[should_panic(expected: 'zone: heart template')]
fn test_refuse_heart_template() {
    let r = ZoneFixture::deploy();
    let [_, _, q2, _, _, _] = r.quotas().quotas;
    assert(q2.kind == quota_kind::HEART, 'quota 2 a Heart');
    r.rewrite_quota(2, Quota { param: 9, ..q2 });
}

// R-42 (BND-01): a pack template whose castes' minimums sum to 0, new, is refused at registration.
#[test]
#[available_gas(l2_gas: 7626413)] // ceil(1.05 × 7263250 measured)
#[should_panic(expected: 'pack: fewest is 0')]
fn test_refuse_pack_fewest_zero() {
    let r = ZoneFixture::bare();
    let none = Pack {
        castes: [
            PackCaste { caste: 3, min: 0, max: 1 }, PackCaste { caste: 1, min: 0, max: 2 },
            Default::default(), Default::default(), Default::default(),
        ],
        level: 1,
    };
    r.refuse(PACK, 3, none.pack());
}

// R-28, a dungeon floor's bound (ENG-R1c's bound 4, built by ENG-09, applied by ENG-R1c-1 in
// `Registry`'s `LOCATION` check): the sample made a floor of `N` 6 in its 3 × 2 rectangle. The
// boundary, and the 4 × 3 sweep, are `test_registry::test_set_record_floor_bounds`.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 53771547)] // ceil(1.05 × 51210997 measured)
#[should_panic(expected: 'location: floor rectangle')]
fn test_refuse_floor_rectangle() {
    let r = ZoneFixture::deploy();
    r
        .refuse(
            LOCATION,
            ZONE,
            Location { kind: location_kind::DUNGEON, target: 6, ..r.location() }.pack(),
        );
}

// R-40 (ENG-R1c-1's bound 5, review t-0099 note 5): the sample made a floor of `N` 5, below 6
// (its 3 × 2 rectangle larger than 5).
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 53771547)] // ceil(1.05 × 51210997 measured)
#[should_panic(expected: 'location: floor under 6 chunks')]
fn test_refuse_floor_few() {
    let r = ZoneFixture::deploy();
    r
        .refuse(
            LOCATION,
            ZONE,
            Location { kind: location_kind::DUNGEON, target: 5, ..r.location() }.pack(),
        );
}

// R-41 (ENG-R1c-1's bound 6, review t-0099 note 5), the `LOCATION` side: the floor (3) that gate 3
// enters at chunk 112, (7, 7), rewritten 7 × 7.
#[test]
#[available_gas(l2_gas: 54336196)] // ceil(1.05 × 51748758 measured)
#[should_panic(expected: 'gate: entry outside rectangle')]
fn test_refuse_gate_entry_outside() {
    let r = ZoneFixture::deploy();
    assert(r.gate(3).destination == 3 && r.gate(3).entry_chunk == 112, 'gate 3 enters the floor');
    r.refuse(LOCATION, 3, plain(location_kind::DUNGEON, 7, 7, 6).pack());
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54543077)] // ceil(1.05 × 51945787 measured)
#[should_panic(expected: 'zone: quota kind')]
fn test_refuse_quota_kind() {
    let r = ZoneFixture::deploy();
    let [_, q1, _, _, _, _] = r.quotas().quotas;
    r.rewrite_quota(1, Quota { kind: quota_kind::EXIT, ..q1 });
}

// R-30 (D-220): a 15 × 15 authored zone, every chunk a candidate of each of six quotas of 112:
// 672 draws, above 640.
#[test]
#[available_gas(l2_gas: 169247465)] // ceil(1.05 × 161188061 measured)
#[should_panic(expected: 'zone: quota draws')]
fn test_refuse_quota_draws() {
    let r = ZoneFixture::deploy();
    let wide = plain(location_kind::ZONE, 15, 15, 0).with_map(map::AUTHORED);
    r.admin.set_record(LOCATION, 4, Location { entry_tile: 112, ..wide }.pack());
    let every = OutlineTrait::rectangle(15, 15);
    r.admin.set_record(CANDIDATES, 8, Candidates { sets: [every, every, every] }.pack());
    r.admin.set_record(CANDIDATES, 9, Candidates { sets: [every, every, every] }.pack());
    let quota = Quota { kind: quota_kind::COLLECTOR, param: 1, count: 112 };
    let heart = Quota { kind: quota_kind::HEART, param: 1, count: 112 };
    let quotas = QuotaSet {
        quotas: [
            quota, Quota { kind: quota_kind::VEIN, param: 0, count: 112 },
            Quota { kind: quota_kind::LANDMARK, param: 1, count: 112 }, heart, heart,
            Quota { kind: quota_kind::LANDMARK, param: 2, count: 112 },
        ],
    };
    r.refuse(QUOTAS, 4, quotas.pack());
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54130156)] // ceil(1.05 × 51552529 measured)
#[should_panic(expected: 'candidates: outside the set')]
fn test_refuse_candidates_outside() {
    let r = ZoneFixture::deploy();
    let [c0, c1, c2] = r.candidates();
    r.rewrite_candidates([c0 + BoardTrait::pow(3), c1, c2]);
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 53763614)] // ceil(1.05 × 51203441 measured)
#[should_panic(expected: 'bridge: deck empty')]
fn test_refuse_bridge_deck() {
    let r = ZoneFixture::deploy();
    r.rewrite_bridge(Bridge { deck: 0, ..r.bridge() });
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 53763614)] // ceil(1.05 × 51203441 measured)
#[should_panic(expected: 'bridge: end')]
fn test_refuse_bridge_end() {
    let r = ZoneFixture::deploy();
    let bridge = r.bridge();
    let (a, _) = bridge.ends;
    r.rewrite_bridge(Bridge { ends: (a, a), ..bridge });
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54004982)] // ceil(1.05 × 51433316 measured)
#[should_panic(expected: 'bridge: end not floor')]
fn test_refuse_bridge_floor() {
    let r = ZoneFixture::deploy();
    let bridge = r.bridge();
    let (_, b) = bridge.ends;
    r.rewrite_bridge(Bridge { ends: (first_wall(@r.chunk(15)), b), ..bridge });
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54112011)] // ceil(1.05 × 51535248 measured)
#[should_panic(expected: 'bridge: end not by the deck')]
fn test_refuse_bridge_apart() {
    let r = ZoneFixture::deploy();
    let bridge = r.bridge();
    let (_, b) = bridge.ends;
    r.rewrite_bridge(Bridge { ends: (first_floor(@r.chunk(15)), b), ..bridge });
}

// R-34 extended (ADR-0008 rule 1), its reverse check: chunk 15's plane rewritten with its
// bridge's deck as wall.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 55348262)] // ceil(1.05 × 52712630 measured)
#[should_panic(expected: 'bridge: deck not floor')]
fn test_refuse_bridge_deck_floor() {
    let r = ZoneFixture::deploy();
    let record = r.chunk(15);
    r
        .rewrite_chunk(
            15, ZoneChunk { walls: BoardTrait::or(record.walls, r.bridge().deck), ..record },
        );
}

// R-37 (ADR-0008 rule 5), its reverse check: a chest on the bridge's first end.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 55485120)] // ceil(1.05 × 52842971 measured)
#[should_panic(expected: 'bridge: tile taken')]
fn test_refuse_bridge_tile_taken() {
    let r = ZoneFixture::deploy();
    let record = r.chunk(15);
    let (a, _) = r.bridge().ends;
    let [o0, o1, _] = record.objects;
    assert(o0.kind == 0 && o1.kind == 0, 'room for a chest');
    let chest = Object { tile: a, kind: object::CHEST, state: 0, param: 0 };
    r.rewrite_chunk(15, ZoneChunk { objects: [chest, o1, Default::default()], ..record });
}

// R-37 at a `GATE` write: gate 3 moved to chunk 15, named there, anchored on the bridge's end.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 56900050)] // ceil(1.05 × 54190523 measured)
#[should_panic(expected: 'bridge: tile taken')]
fn test_refuse_gate_on_a_bridge() {
    let r = ZoneFixture::deploy();
    let record = r.chunk(15);
    r.admin.set_record(ZONE_CHUNK, ZONE * 256 + 15, ZoneChunk { gates: [4, 0], ..record }.pack());
    let (a, _) = r.bridge().ends;
    let gate = Gate { anchor_chunk: 15, anchor_tile: a, ..r.gate(3) };
    r.refuse(GATE, 4, gate.pack());
}

// R-35's reverse check: chunk 15's count of bridges lowered below its written bridge.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54872853)] // ceil(1.05 × 52259860 measured)
#[should_panic(expected: 'bridge: index')]
fn test_refuse_bridge_index() {
    let r = ZoneFixture::deploy();
    r.rewrite_chunk(15, ZoneChunk { bridges: 0, ..r.chunk(15) });
}

// R-35 forward: a second bridge in chunk 15, which counts one.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 53851604)] // ceil(1.05 × 51287241 measured)
#[should_panic(expected: 'bridge: index')]
fn test_refuse_bridge_past_the_count() {
    let r = ZoneFixture::deploy();
    r.refuse(BRIDGE, ZONE * 4096 + 15 * 16 + 1, r.bridge().pack());
}

// A `ZONE_CHUNK`'s parent: its location, and a chunk below 225.
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 53493291)] // ceil(1.05 × 50945991 measured)
#[should_panic(expected: 'registry: no parent')]
fn test_refuse_zone_chunk_without_location() {
    let r = ZoneFixture::deploy();
    r.refuse(ZONE_CHUNK, 9 * 256, r.chunk(1).pack());
}

#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 54038430)] // ceil(1.05 × 51465171 measured)
#[should_panic(expected: 'zone chunk: reserved plane')]
fn test_refuse_reserved_plane() {
    let r = ZoneFixture::deploy();
    let parts = r.chunk(1).pack();
    r
        .refuse(
            ZONE_CHUNK, ZONE * 256 + 1, array![*parts[0] + BoardTrait::pow(225), *parts[1]].span(),
        );
}

// The marker: a value this reader does not know is refused (format version 1).
#[test]
// gas: raised, ENG-R1c-1: the fixture's gates indexed, its writes under the shared bounds
#[available_gas(l2_gas: 53703029)] // ceil(1.05 × 51145741 measured)
#[should_panic(expected: 'location: map')]
fn test_refuse_unknown_map() {
    let r = ZoneFixture::deploy();
    let parts = r.location().pack();
    // The marker (bits 144–151) raised from 1 to 2
    let unknown = *parts[0] + 0x10000 * 0x100000000000000000000000000000000;
    r.refuse(LOCATION, ZONE, array![unknown, *parts[1]].span());
}

// --- Generated zones, dungeon floors and gates (ENG-R1c-1) --------------------------------------
//
// The bounds a generated zone or a dungeon floor shares with an authored zone, on `bare`'s
// registry: location 2 written as each test needs. Each case of `checks.json` refuses the first
// value past the bound after writing the last one within it.

/// Six quotas of one kind (a vein: no template), the counts given.
fn veins(counts: [u8; 6]) -> QuotaSet {
    let [c0, c1, c2, c3, c4, c5] = counts;
    let vein = Quota { kind: quota_kind::VEIN, param: 0, count: 0 };
    QuotaSet {
        quotas: [
            Quota { count: c0, ..vein }, Quota { count: c1, ..vein }, Quota { count: c2, ..vein },
            Quota { count: c3, ..vein }, Quota { count: c4, ..vein }, Quota { count: c5, ..vein },
        ],
    }
}

/// One quota, the five others none.
fn one(quota: Quota) -> QuotaSet {
    QuotaSet {
        quotas: [
            quota, Default::default(), Default::default(), Default::default(), Default::default(),
            Default::default(),
        ],
    }
}

fn chunk_set(chunks: felt252) -> Span<felt252> {
    let wide: u256 = chunks.into();
    OutlineRecord::pack(@OutlineTrait::new(wide.low, wide.high))
}

// R-11 for a generated zone: in a 2 × 1 zone, chunks 0 and 1 accepted, chunk 2 (cx 2) refused.
#[test]
#[available_gas(l2_gas: 11916408)] // ceil(1.05 × 11348960 measured)
#[should_panic(expected: 'zone: set outside rectangle')]
fn test_refuse_generated_set_outside() {
    let r = ZoneFixture::bare();
    r.admin.set_record(LOCATION, 2, plain(location_kind::ZONE, 2, 1, 0).pack());
    r.admin.set_record(OUTLINE, 2 * 256 + 255, chunk_set(3));
    r.refuse(OUTLINE, 2 * 256 + 255, chunk_set(7));
}

// R-12 for a generated zone: in a 1 × 1 zone, a count of 1 accepted, 2 refused.
#[test]
#[available_gas(l2_gas: 11944215)] // ceil(1.05 × 11375442 measured)
#[should_panic(expected: 'zone: count above members')]
fn test_refuse_generated_count_above_members() {
    let r = ZoneFixture::bare();
    r.admin.set_record(LOCATION, 2, plain(location_kind::ZONE, 1, 1, 0).pack());
    r.admin.set_record(QUOTAS, 2, one(Quota { kind: quota_kind::VEIN, param: 0, count: 1 }).pack());
    r.refuse(QUOTAS, 2, one(Quota { kind: quota_kind::VEIN, param: 0, count: 2 }).pack());
}

// R-12 for a dungeon floor, whose members are its `N` chunks (its outline): `N` 6, an exit of 6
// accepted, 7 refused.
#[test]
#[available_gas(l2_gas: 11942623)] // ceil(1.05 × 11373926 measured)
#[should_panic(expected: 'zone: count above members')]
fn test_refuse_floor_count_above_members() {
    let r = ZoneFixture::bare();
    r.admin.set_record(LOCATION, 2, plain(location_kind::DUNGEON, 15, 15, 6).pack());
    r.admin.set_record(QUOTAS, 2, one(Quota { kind: quota_kind::EXIT, param: 1, count: 6 }).pack());
    r.refuse(QUOTAS, 2, one(Quota { kind: quota_kind::EXIT, param: 1, count: 7 }).pack());
}

// R-27 for a generated zone: a Heart naming the cubs (at least 1 at their fewest) accepted, one
// naming a template the registry does not hold refused.
#[test]
#[available_gas(l2_gas: 12676243)] // ceil(1.05 × 12072612 measured)
#[should_panic(expected: 'zone: heart template')]
fn test_refuse_generated_heart_template() {
    let r = ZoneFixture::bare();
    r.admin.set_record(LOCATION, 2, plain(location_kind::ZONE, 2, 2, 0).pack());
    r
        .admin
        .set_record(QUOTAS, 2, one(Quota { kind: quota_kind::HEART, param: 2, count: 1 }).pack());
    r.refuse(QUOTAS, 2, one(Quota { kind: quota_kind::HEART, param: 9, count: 1 }).pack());
}

// R-27's reverse check for a generated zone: the cubs, which its Heart names, rewritten with one
// goblin at their fewest accepted, with none refused.
#[test]
#[available_gas(l2_gas: 12841673)] // ceil(1.05 × 12230164 measured)
#[should_panic(expected: 'zone: heart template')]
fn test_refuse_generated_pack_rewrite_heart() {
    let r = ZoneFixture::bare();
    r.admin.set_record(LOCATION, 2, plain(location_kind::ZONE, 2, 2, 0).pack());
    r
        .admin
        .set_record(QUOTAS, 2, one(Quota { kind: quota_kind::HEART, param: 2, count: 1 }).pack());
    let fewest_one = Pack {
        castes: [
            PackCaste { caste: 3, min: 0, max: 1 }, PackCaste { caste: 1, min: 1, max: 2 },
            Default::default(), Default::default(), Default::default(),
        ],
        level: 1,
    };
    r.admin.set_record(PACK, 2, fewest_one.pack());
    let fewest_none = Pack {
        castes: [
            PackCaste { caste: 3, min: 0, max: 1 }, PackCaste { caste: 1, min: 0, max: 2 },
            Default::default(), Default::default(), Default::default(),
        ],
        level: 1,
    };
    r.refuse(PACK, 2, fewest_none.pack());
}

// R-30 for a generated zone (D-221): a 15 × 15 zone (225 members), six veins of 112, 112, 112,
// 112, 112 and 80 draw 640 times together, accepted; 81 for the last, 641, refused.
#[test]
#[available_gas(l2_gas: 12486025)] // ceil(1.05 × 11891452 measured)
#[should_panic(expected: 'zone: quota draws')]
fn test_refuse_generated_quota_draws() {
    let r = ZoneFixture::bare();
    r.admin.set_record(LOCATION, 2, plain(location_kind::ZONE, 15, 15, 0).pack());
    r.admin.set_record(QUOTAS, 2, veins([112, 112, 112, 112, 112, 80]).pack());
    r.refuse(QUOTAS, 2, veins([112, 112, 112, 112, 112, 81]).pack());
}

// The reverse checks of R-11, R-12 and R-30 for a generated zone and a dungeon floor: the record
// the quotas or the chunk set are checked against, rewritten past the bound, is refused.
#[test]
#[available_gas(l2_gas: 39432548)] // ceil(1.05 × 37554807 measured)
fn test_generated_reverse_checks() {
    let r = ZoneFixture::bare();
    // A 2 × 1 zone, its chunk set both chunks, a vein on each: the set or the rectangle shrunk
    r.admin.set_record(LOCATION, 2, plain(location_kind::ZONE, 2, 1, 0).pack());
    r.admin.set_record(OUTLINE, 2 * 256 + 255, chunk_set(3));
    r.admin.set_record(QUOTAS, 2, one(Quota { kind: quota_kind::VEIN, param: 0, count: 2 }).pack());
    r.refused(OUTLINE, 2 * 256 + 255, chunk_set(1), 'zone: count above members');
    r
        .refused(
            LOCATION, 2, plain(location_kind::ZONE, 1, 1, 0).pack(), 'zone: set outside rectangle',
        );
    // R-30 against a chunk set grown: in a 15 × 15 zone, a set of 14 rows (210 members) and six
    // veins of 112 draw 6 × 98 = 588 times, accepted; the whole rectangle, 6 × 112 = 672, refused
    r.admin.set_record(LOCATION, 3, plain(location_kind::ZONE, 15, 15, 0).pack());
    r.admin.set_record(OUTLINE, 3 * 256 + 255, chunk_set(OutlineTrait::rectangle(15, 14)));
    r.admin.set_record(QUOTAS, 3, veins([112, 112, 112, 112, 112, 112]).pack());
    r
        .refused(
            OUTLINE, 3 * 256 + 255, chunk_set(OutlineTrait::rectangle(15, 15)), 'zone: quota draws',
        );
    // Without a chunk set the rectangle is the members: a vein of 112, the zone shrunk to 10 × 10
    r.admin.set_record(LOCATION, 4, plain(location_kind::ZONE, 15, 15, 0).pack());
    r
        .admin
        .set_record(QUOTAS, 4, one(Quota { kind: quota_kind::VEIN, param: 0, count: 112 }).pack());
    r.admin.set_record(LOCATION, 4, plain(location_kind::ZONE, 11, 11, 0).pack());
    r
        .refused(
            LOCATION, 4, plain(location_kind::ZONE, 10, 11, 0).pack(), 'zone: count above members',
        );
    // A floor's members are its `N`: an exit of 7 at `N` 7, `N` lowered to 6
    r.admin.set_record(LOCATION, 5, plain(location_kind::DUNGEON, 15, 15, 7).pack());
    r.admin.set_record(QUOTAS, 5, one(Quota { kind: quota_kind::EXIT, param: 1, count: 7 }).pack());
    r
        .refused(
            LOCATION,
            5,
            plain(location_kind::DUNGEON, 15, 15, 6).pack(),
            'zone: count above members',
        );
}

/// A gate from the town (1) to `destination`, entering at `entry`.
fn gate_to(destination: u16, entry: u8) -> Span<felt252> {
    Gate {
        source: 1,
        destination,
        anchor_chunk: 0,
        anchor_tile: 0,
        entry_chunk: entry,
        entry_tile: 112,
        kind: 1,
        rank: 0,
        quest: 0,
    }
        .pack()
}

// R-41 (ENG-R1c-1's bound 6), both sides and the index: into an 8 × 8 floor, chunk 112 (7, 7)
// accepted, 113 (8, 7) and 127 (7, 8) refused; into the town (no map), any chunk; into a location
// not written yet, any chunk, then its `LOCATION` refused 7 × 7 and accepted 8 × 8. Two gates
// enter the floor at 112: it shrinks to 7 × 1 only once both have left that chunk, one for another
// destination, the other for chunk 0 (a chunk's bit leaves `gate_entries` with its last gate).
#[test]
#[available_gas(l2_gas: 31714653)] // ceil(1.05 × 30204431 measured)
fn test_gate_entry_bounds() {
    let r = ZoneFixture::bare();
    r.admin.set_record(LOCATION, 2, plain(location_kind::DUNGEON, 8, 8, 6).pack());
    r.admin.set_record(GATE, 1, gate_to(2, 112));
    r.refused(GATE, 2, gate_to(2, 113), 'gate: entry outside rectangle');
    r.refused(GATE, 2, gate_to(2, 127), 'gate: entry outside rectangle');
    r.admin.set_record(GATE, 2, gate_to(1, 224));
    r.admin.set_record(GATE, 3, gate_to(3, 112));
    r
        .refused(
            LOCATION,
            3,
            plain(location_kind::DUNGEON, 7, 7, 6).pack(),
            'gate: entry outside rectangle',
        );
    r.admin.set_record(LOCATION, 3, plain(location_kind::DUNGEON, 8, 8, 6).pack());
    // Two gates at (2, 112)
    r.admin.set_record(GATE, 4, gate_to(2, 112));
    r
        .refused(
            LOCATION,
            2,
            plain(location_kind::DUNGEON, 7, 8, 6).pack(),
            'gate: entry outside rectangle',
        );
    r.admin.set_record(GATE, 1, gate_to(3, 112));
    r
        .refused(
            LOCATION,
            2,
            plain(location_kind::DUNGEON, 7, 1, 6).pack(),
            'gate: entry outside rectangle',
        );
    r.admin.set_record(GATE, 4, gate_to(2, 0));
    r.admin.set_record(LOCATION, 2, plain(location_kind::DUNGEON, 7, 1, 6).pack());
}

/// `gate_to(destination, 224)` with its entry chunk raised to `entry`: a record `GateRecord::pack`
/// refuses (an entry chunk is below 225) but the Registry reads as it is written.
fn gate_entering_chunk(destination: u16, entry: u8) -> Span<felt252> {
    let raw: felt252 = *gate_to(destination, 224).at(0) + (entry - 224).into() * 0x1000000000000;
    array![raw].span()
}

// R-43 (BND-01, D-258) and R-41 at the board's edge (review t-0150 note 2): an entry chunk of 225,
// the first past the board, or 255, the last a byte holds, is refused whatever the destination (a
// map, a hub, a location not yet written: R-41 alone reads only the first); 224, the last chunk,
// is accepted.
#[test]
#[available_gas(l2_gas: 27139221)] // ceil(1.05 × 25846877 measured)
fn test_gate_entry_past_the_board() {
    let r = ZoneFixture::bare();
    r.admin.set_record(LOCATION, 2, plain(location_kind::DUNGEON, 15, 15, 6).pack());
    r.admin.set_record(GATE, 1, gate_entering_chunk(2, 224));
    // The town (1) is a hub; location 9 is not written
    r.admin.set_record(GATE, 2, gate_entering_chunk(1, 224));
    r.admin.set_record(GATE, 3, gate_entering_chunk(9, 224));
    for destination in array![1_u16, 2, 9] {
        r.refused(GATE, 4, gate_entering_chunk(destination, 225), 'gate: entry chunk');
        r.refused(GATE, 4, gate_entering_chunk(destination, 255), 'gate: entry chunk');
    }
    let small = plain(location_kind::DUNGEON, 8, 8, 6);
    r.admin.set_record(LOCATION, 3, small.pack());
    r.refused(GATE, 4, gate_entering_chunk(3, 225), 'gate: entry chunk');
    r.refused(GATE, 4, gate_entering_chunk(3, 255), 'gate: entry chunk');
    // R-41 still reads a chunk on the board outside the rectangle
    r.refused(GATE, 4, gate_entering_chunk(3, 224), 'gate: entry outside rectangle');
}

// R-43 as a case of the table: the Registry's alone (the converter's `GateRecord::pack` refuses
// it).
#[test]
#[available_gas(l2_gas: 7747991)] // ceil(1.05 × 7379039 measured)
#[should_panic(expected: 'gate: entry chunk')]
fn test_refuse_gate_entry_chunk() {
    let r = ZoneFixture::bare();
    r.refuse(GATE, 1, gate_entering_chunk(1, 225));
}

/// A registry with no zone checks yet: the town only, as `bare` less its class and its packs.
fn unchecked() -> Registry {
    let contract = declare("Registry").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![ADMIN]).unwrap();
    start_cheat_caller_address(address, ADMIN.try_into().unwrap());
    let r = Registry {
        address,
        admin: IRegistryAdminDispatcher { contract_address: address },
        safe: IRegistryAdminSafeDispatcher { contract_address: address },
        read: IRegistryReadDispatcher { contract_address: address },
    };
    r.admin.set_record(LOCATION, 1, plain(location_kind::TOWN, 0, 0, 0).pack());
    r
}

// BND-01: a `GATE` is refused until `set_zone_checks`: `index` could not count it.
#[test]
#[available_gas(l2_gas: 3928733)] // ceil(1.05 × 3741650 measured)
#[should_panic(expected: 'registry: no zone checks')]
fn test_refuse_gate_without_zone_checks() {
    let r = unchecked();
    r.refuse(GATE, 1, gate_to(1, 0));
}

// BND-01 (review t-0153, minor 1): a chunk set is refused until the class is set, so a `LOCATION`
// (4 x 4, generated) and an `OUTLINE` of chunk 255 with a chunk outside it cannot both be written
// unchecked; a border mask, which R-20 checks against a `ZONE_CHUNK`, is not refused.
#[test]
#[available_gas(l2_gas: 11876464)] // ceil(1.05 × 11310918 measured)
fn test_chunk_set_cannot_precede_the_class() {
    let r = unchecked();
    r.admin.set_record(LOCATION, 2, plain(location_kind::ZONE, 4, 4, 0).pack());
    // Chunk 4 is (4, 0): outside the 4 x 4 rectangle
    r.refused(OUTLINE, 2 * 256 + 255, chunk_set(0x13), 'registry: no zone checks');
    r.admin.set_record(OUTLINE, 2 * 256 + 16, chunk_set(1));
    r.admin.set_zone_checks(class("ZoneChecks"));
    r.refused(OUTLINE, 2 * 256 + 255, chunk_set(0x13), 'zone: set outside rectangle');
    r.admin.set_record(OUTLINE, 2 * 256 + 255, chunk_set(0xF));
}

// BND-01: and so is a `QUOTAS` (`heart_packs`).
#[test]
#[available_gas(l2_gas: 4070283)] // ceil(1.05 × 3876460 measured)
#[should_panic(expected: 'registry: no zone checks')]
fn test_refuse_quotas_without_zone_checks() {
    let r = unchecked();
    r.refuse(QUOTAS, 1, one(Quota { kind: quota_kind::VEIN, param: 0, count: 1 }).pack());
}

// BND-01: the order the review of #422 found (a gate written before the class, so unindexed, then a
// rewrite of another gate clearing the bit, then a LOCATION shrink passing R-41) cannot be
// produced: the first gate is refused, the other kinds are not, and once the class is set both
// gates enter the chunk, the shrink is refused after either is rewritten away.
#[test]
#[available_gas(l2_gas: 17061120)] // ceil(1.05 × 16248685 measured)
fn test_unindexed_gate_cannot_hide_an_entry() {
    let r = unchecked();
    r.admin.set_record(LOCATION, 2, plain(location_kind::DUNGEON, 8, 8, 6).pack());
    r.refused(GATE, 1, gate_to(2, 112), 'registry: no zone checks');
    assert(r.admin.last_id(GATE) == 0, 'no gate written');
    r.admin.set_zone_checks(class("ZoneChecks"));
    // Gate A, then gate B, enter the same chunk; A is rewritten to enter elsewhere
    r.admin.set_record(GATE, 1, gate_to(2, 112));
    r.admin.set_record(GATE, 2, gate_to(2, 112));
    r.admin.set_record(GATE, 1, gate_to(2, 0));
    r
        .refused(
            LOCATION,
            2,
            plain(location_kind::DUNGEON, 7, 8, 6).pack(),
            'gate: entry outside rectangle',
        );
    r.admin.set_record(GATE, 2, gate_to(2, 0));
    r.admin.set_record(LOCATION, 2, plain(location_kind::DUNGEON, 7, 8, 6).pack());
}
