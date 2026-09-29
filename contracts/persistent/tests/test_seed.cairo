// ENG-03: the test region (`contracts/seed/test-region.json`, described in
// `contracts/seed/README.md`)
// written through `set_record` and read back through one `bundle`. `write_seed` is the helper later
// tests build on (ENG-05, ENG-06): it reads the data file, packs every record with
// `grimworld_logic::world`, and writes it as the administrator.
//
// snforge's `read_json` puts an object's values in the alphabetical order of its keys, flattens
// nested arrays, drops empty ones and writes a one-element array without its length: the file
// therefore holds, per kind, one flat array (a record a line, fixed columns, never empty) and the
// names of its columns, and `write_seed` reads the stream with a cursor and checks the names.
use grimworld_logic::content::{GATE, LOCATION, OUTLINE, REGION, parts};
use grimworld_logic::interface::{IRegistryReadDispatcher, IRegistryReadDispatcherTrait};
use grimworld_logic::packing::Lanes16;
use grimworld_logic::world::{
    CAVE, CHUNK_SET, DUNGEON, GATE_FLOOR, GATE_HUB, GATE_LINK, Gate, Location, MEADOW, Outline,
    Region, TOWN, ZONE, outline_id, pack_gate, pack_location, pack_outline, pack_region,
    unpack_gate, unpack_location, unpack_outline, unpack_region,
};
use grimworld_persistent::systems::registry::{
    IRegistryAdminDispatcher, IRegistryAdminDispatcherTrait,
};
use snforge_std::fs::{FileTrait, read_json};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

const ADMIN: felt252 = 0xad;

/// A region's row: four numbers and its name.
#[derive(Drop)]
struct RegionRow {
    numbers: Span<felt252>,
    name: ByteArray,
}

/// The file, in the order `read_json` gives its keys.
#[derive(Drop)]
struct Seed {
    gate_fields: Array<ByteArray>,
    gates: Span<felt252>,
    location_fields: Array<ByteArray>,
    locations: Span<felt252>,
    outline_fields: Array<ByteArray>,
    outlines: Span<felt252>,
    region_fields: Array<ByteArray>,
    regions: Array<RegionRow>,
}

/// What `write_seed` wrote, in the order written: `(kind, id)` of every record, and the felts of
/// all of them in the same order.
#[derive(Drop)]
pub struct Written {
    pub requests: Array<(u8, u32)>,
    pub felts: Array<felt252>,
}

fn pop_len(ref stream: Span<felt252>) -> u32 {
    (*stream.pop_front().expect('seed: truncated')).try_into().expect('seed: length')
}

fn read_names(ref stream: Span<felt252>) -> Array<ByteArray> {
    let mut names: Array<ByteArray> = array![];
    for _ in 0..pop_len(ref stream) {
        names.append(Serde::<ByteArray>::deserialize(ref stream).expect('seed: a column name'));
    }
    names
}

fn read_numbers(ref stream: Span<felt252>) -> Span<felt252> {
    let count = pop_len(ref stream);
    assert(stream.len() >= count, 'seed: truncated');
    let numbers = stream.slice(0, count);
    stream = stream.slice(count, stream.len() - count);
    numbers
}

fn load_seed() -> Seed {
    let file = FileTrait::new("../seed/test-region.json");
    let felts = read_json(@file);
    let mut stream = felts.span();
    let gate_fields = read_names(ref stream);
    let gates = read_numbers(ref stream);
    let location_fields = read_names(ref stream);
    let locations = read_numbers(ref stream);
    let outline_fields = read_names(ref stream);
    let outlines = read_numbers(ref stream);
    let region_fields = read_names(ref stream);
    // Five elements a row: four numbers, then the name (a `ByteArray` of several felts).
    let (count, rest) = DivRem::div_rem(pop_len(ref stream), 5);
    assert(rest == 0, 'seed: a region row is short');
    let mut regions: Array<RegionRow> = array![];
    for _ in 0..count {
        let numbers = stream.slice(0, 4);
        stream = stream.slice(4, stream.len() - 4);
        let name = Serde::<ByteArray>::deserialize(ref stream).expect('seed: region name');
        regions.append(RegionRow { numbers, name });
    }
    assert(stream.len() == 0, 'seed: unread values');
    Seed {
        gate_fields,
        gates,
        location_fields,
        locations,
        outline_fields,
        outlines,
        region_fields,
        regions,
    }
}

/// The file's column names must be these, in this order; returns the number of rows.
fn check_columns(
    fields: @Array<ByteArray>, expected: Array<ByteArray>, rows: Span<felt252>,
) -> u32 {
    assert(fields.len() == expected.len(), 'seed: columns');
    for i in 0..expected.len() {
        assert(fields[i] == expected[i], 'seed: column name');
    }
    let (count, rest) = DivRem::div_rem(rows.len(), expected.len().try_into().unwrap());
    assert(rest == 0, 'seed: a row is short');
    count
}

fn at<T, +TryInto<felt252, T>>(row: Span<felt252>, i: u32) -> T {
    (*row[i]).try_into().expect('seed: value out of range')
}

fn short_string(name: @ByteArray) -> felt252 {
    assert(name.len() <= 15, 'seed: region name');
    let mut word: felt252 = 0;
    for i in 0..name.len() {
        word = word * 256 + name.at(i).unwrap().into();
    }
    word
}

fn set_piece_columns() -> Array<ByteArray> {
    array![
        "set_piece_1", "set_piece_2", "set_piece_3", "set_piece_4", "set_piece_5", "set_piece_6",
        "set_piece_7", "set_piece_8", "set_piece_9", "set_piece_10", "set_piece_11", "set_piece_12",
        "set_piece_13", "set_piece_14", "set_piece_15",
    ]
}

fn location_columns() -> Array<ByteArray> {
    let mut columns: Array<ByteArray> = array![
        "id", "kind", "region", "biome", "level_min", "level_max", "rank", "width", "height",
        "target", "floors", "next_floor", "spawn_table", "sealed", "entry_chunk", "entry_tile",
    ];
    for name in set_piece_columns() {
        columns.append(name);
    }
    columns
}

fn location_of(row: Span<felt252>) -> Location {
    let s = 16;
    let set_pieces = Lanes16 {
        lanes: [
            at(row, s), at(row, s + 1), at(row, s + 2), at(row, s + 3), at(row, s + 4),
            at(row, s + 5), at(row, s + 6), at(row, s + 7), at(row, s + 8), at(row, s + 9),
            at(row, s + 10), at(row, s + 11), at(row, s + 12), at(row, s + 13), at(row, s + 14),
        ],
    };
    let sealed: u8 = at(row, 13);
    assert(sealed <= 1, 'seed: sealed is 0 or 1');
    Location {
        kind: at(row, 1),
        region: at(row, 2),
        biome: at(row, 3),
        level_min: at(row, 4),
        level_max: at(row, 5),
        rank: at(row, 6),
        width: at(row, 7),
        height: at(row, 8),
        target: at(row, 9),
        floors: at(row, 10),
        next_floor: at(row, 11),
        spawn_table: at(row, 12),
        sealed: sealed == 1,
        entry_chunk: at(row, 14),
        entry_tile: at(row, 15),
        set_pieces,
    }
}

// A test helper, not a contract: `u256` only to split the rows' sum into its two limbs.
fn outline_of(row: Span<felt252>) -> Outline {
    let mut bits: u256 = 0;
    let mut factor: u256 = 1;
    for i in 2..17_u32 {
        let value: u16 = at(row, i);
        assert(value < 0x8000, 'seed: outline row');
        bits += value.into() * factor;
        factor *= 0x8000;
    }
    Outline { low: bits.low, high: bits.high }
}

fn gate_of(row: Span<felt252>) -> Gate {
    Gate {
        source: at(row, 1),
        destination: at(row, 2),
        anchor_chunk: at(row, 3),
        anchor_tile: at(row, 4),
        entry_chunk: at(row, 5),
        entry_tile: at(row, 6),
        kind: at(row, 7),
        rank: at(row, 8),
        quest: at(row, 9),
    }
}

/// The test region's records, packed, in the order they are written: regions, locations, outlines
/// (whose parent location must exist first), then gates.
pub fn seed_records() -> Written {
    let seed = load_seed();
    let mut written = Written { requests: array![], felts: array![] };

    let region_columns: Array<ByteArray> = array!["id", "town", "book", "first_location", "name"];
    assert(seed.region_fields == region_columns, 'seed: region columns');
    for region_row in seed.regions.span() {
        let row = *region_row.numbers;
        let id: u32 = at(row, 0);
        let region = Region {
            town: at(row, 1),
            book: at(row, 2),
            first_location: at(row, 3),
            name: short_string(region_row.name),
        };
        let word = pack_region(region);
        written.requests.append((REGION, id));
        written.felts.append(word);
    }

    let width = 31;
    let rows = check_columns(@seed.location_fields, location_columns(), seed.locations);
    for i in 0..rows {
        let row = seed.locations.slice(width * i, width);
        let id: u32 = at(row, 0);
        let (a, b) = pack_location(location_of(row));
        written.requests.append((LOCATION, id));
        written.felts.append(a);
        written.felts.append(b);
    }

    let outline_columns: Array<ByteArray> = array![
        "location", "chunk", "row_0", "row_1", "row_2", "row_3", "row_4", "row_5", "row_6", "row_7",
        "row_8", "row_9", "row_10", "row_11", "row_12", "row_13", "row_14",
    ];
    let rows = check_columns(@seed.outline_fields, outline_columns, seed.outlines);
    for i in 0..rows {
        let row = seed.outlines.slice(17 * i, 17);
        let id = outline_id(at(row, 0), at(row, 1));
        let word = pack_outline(outline_of(row));
        written.requests.append((OUTLINE, id));
        written.felts.append(word);
    }

    let gate_columns: Array<ByteArray> = array![
        "id", "source", "destination", "anchor_chunk", "anchor_tile", "entry_chunk", "entry_tile",
        "kind", "rank", "quest",
    ];
    let rows = check_columns(@seed.gate_fields, gate_columns, seed.gates);
    for i in 0..rows {
        let row = seed.gates.slice(10 * i, 10);
        let id: u32 = at(row, 0);
        let word = pack_gate(gate_of(row));
        written.requests.append((GATE, id));
        written.felts.append(word);
    }
    written
}

/// Writes `records` into `registry` as `ADMIN`, one `set_record` a record.
pub fn write_records(registry: ContractAddress, records: @Written) {
    let admin = IRegistryAdminDispatcher { contract_address: registry };
    start_cheat_caller_address(registry, ADMIN.try_into().unwrap());
    let mut felts = records.felts.span();
    for request in records.requests.span() {
        let (kind, id) = *request;
        let count: u32 = parts(kind).into();
        admin.set_record(kind, id, felts.slice(0, count));
        felts = felts.slice(count, felts.len() - count);
    }
    stop_cheat_caller_address(registry);
}

/// Writes the test region into `registry` as `ADMIN`; returns what it wrote.
pub fn write_seed(registry: ContractAddress) -> Written {
    let written = seed_records();
    write_records(registry, @written);
    written
}

fn deploy() -> ContractAddress {
    let class = declare("Registry").unwrap().contract_class();
    let (address, _) = class.deploy(@array![ADMIN]).unwrap();
    address
}

// The test region, written and read back in one `bundle` (AC-4): 13 records, 17 slots.
#[test]
#[available_gas(l2_gas: 22435875)] // ceil(1.05 × 21367500 measured)
fn test_seed_written_and_read_back() {
    let registry = deploy();
    let written = write_seed(registry);
    assert(written.requests.len() == 13, '13 records');
    assert(written.felts.len() == 17, '17 slots');
    let read = IRegistryReadDispatcher { contract_address: registry };
    let (version, felts) = read.bundle(written.requests.span());
    assert(version == 13, 'one version a record');
    assert(felts == written.felts.span(), 'read back as written');
    let admin = IRegistryAdminDispatcher { contract_address: registry };
    assert(admin.last_id(REGION) == 1, 'one region');
    assert(admin.last_id(LOCATION) == 4, 'four locations');
    assert(admin.last_id(GATE) == 5, 'five gates');
    assert(admin.last_id(OUTLINE) == 0, 'outlines are composite');

    // What the file says, field by field, through the layouts.
    let region = unpack_region(*felts[0]);
    assert(region.town == 1 && region.first_location == 1 && region.book == 0, 'region');
    assert(region.name == 'Test Region', 'region: name');
    let town = unpack_location(*felts[1], *felts[2]);
    assert(town.kind == TOWN && town.region == 1 && town.width == 0, 'town');
    let zone = unpack_location(*felts[3], *felts[4]);
    assert(zone.kind == ZONE && zone.biome == MEADOW, 'zone');
    assert(zone.level_min == 1 && zone.level_max == 3, 'zone: band');
    assert(zone.width == 3 && zone.height == 2, 'zone: size');
    assert(zone.entry_chunk == 0 && zone.entry_tile == 105, 'zone: entry');
    let floor1 = unpack_location(*felts[5], *felts[6]);
    assert(floor1.kind == DUNGEON && floor1.biome == CAVE, 'floor 1');
    assert(floor1.target == 6 && floor1.floors == 2 && floor1.next_floor == 4, 'floor 1: N');
    assert(floor1.entry_chunk == 112 && floor1.entry_tile == 112, 'floor 1: entry (7, 7)');
    assert(floor1.set_pieces == Lanes16 { lanes: [0; 15] }, 'floor 1: no set piece');
    let floor2 = unpack_location(*felts[7], *felts[8]);
    assert(floor2.target == 8 && floor2.next_floor == 0, 'floor 2: last');
    // The zone's chunk set: (0, 0), (1, 0), (2, 0), (0, 1), (1, 1).
    assert(*written.requests[5] == (OUTLINE, 2 * 256 + CHUNK_SET.into()), 'chunk set id');
    let chunks = unpack_outline(*felts[9]);
    assert(chunks == Outline { low: 0x18007, high: 0 }, 'zone: chunk set');
    // Chunk 16's mask: rows 0-9 whole, rows 10-14 columns 0-9; 200 tiles.
    assert(*written.requests[7] == (OUTLINE, 2 * 256 + 16), 'chunk 16 id');
    let mask = unpack_outline(*felts[11]);
    let expected = Outline {
        low: 0xffffffffffffffffffffffffffffffff, high: 0xffc1ff83ff07fe0ffffffff,
    };
    assert(mask == expected, 'chunk 16 mask');
    let hub = unpack_gate(*felts[12]);
    assert(hub.source == 1 && hub.destination == 2 && hub.kind == GATE_HUB, 'gate 1: hub');
    assert(hub.entry_chunk == 0 && hub.entry_tile == 105, 'gate 1: entry');
    let link = unpack_gate(*felts[14]);
    assert(link.source == 2 && link.destination == 3 && link.kind == GATE_LINK, 'gate 3: link');
    assert(link.anchor_chunk == 16 && link.anchor_tile == 110, 'gate 3: anchor');
    let floor = unpack_gate(*felts[16]);
    assert(floor.source == 3 && floor.destination == 4 && floor.kind == GATE_FLOOR, 'gate 5');
}

// The baseline of the next test: the deployment, and the file read and packed.
#[test]
#[available_gas(l2_gas: 6108354)] // ceil(1.05 × 5817480 measured)
fn test_gas_seed_baseline() {
    deploy();
    seed_records();
}

// Writing the whole test region, 13 `set_record` (AC-4): this test less the baseline.
#[test]
#[available_gas(l2_gas: 20306916)] // ceil(1.05 × 19339920 measured)
fn test_gas_seed_write() {
    let registry = deploy();
    write_records(registry, @seed_records());
}

// Writing the same seed again changes nothing: no record changed, the version stays.
#[test]
#[available_gas(l2_gas: 29247026)] // ceil(1.05 × 27854310 measured)
fn test_seed_rewritten_unchanged() {
    let registry = deploy();
    write_seed(registry);
    write_seed(registry);
    let read = IRegistryReadDispatcher { contract_address: registry };
    assert(read.content_version() == 13, 'version kept');
}
